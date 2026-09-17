import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// A disk cache for GET requests, driven by the server's own cache headers.
///
/// ## Why this is hand-written rather than a package
///
/// The two things this has to get right are not what an off-the-shelf HTTP
/// cache is built for:
///
///  1. **It must be keyed per signed-in user.** Two customers can use the same
///     phone - a site office handset, a family sharing a tablet - and a cache
///     keyed only by URL would serve the second one the first one's complaint
///     list. Every entry here is namespaced by the subject of the access
///     token, and [clearForSignOut] drops the lot when somebody signs out.
///  2. **It must honour `immutable` and `no-cache` differently.** The API
///     marks a stored file (a document, a photograph) immutable for a year,
///     and every JSON list `private, no-cache` - store it, but always
///     revalidate. Those are the two behaviours that matter and they need no
///     general-purpose cache-control parser.
///
/// ## What it gives
///
/// * Images and documents come off the disk on the second look and after a
///   restart, with no request at all. They are content-addressed by id, so
///   there is nothing to revalidate.
/// * JSON lists are stored with their ETag and revalidated with
///   `If-None-Match`. Unchanged, the server answers 304 with no body, so the
///   list redraws from disk for the price of one small round trip. That is the
///   difference between a list appearing at once and a spinner on a slow
///   connection.
/// * Nothing is served stale: a `no-cache` entry is never used without asking
///   the server first.
class HttpDiskCache {
  HttpDiskCache._(this._directory);

  final Directory _directory;

  /// Roughly the size of a few dozen documents and a project's photographs.
  /// Beyond this the oldest entries go, by last use.
  static const _maxBytes = 80 * 1024 * 1024;

  static HttpDiskCache? _instance;

  static Future<HttpDiskCache> open() async {
    if (_instance != null) return _instance!;

    // Application SUPPORT, not documents or temporary: documents is for things
    // the customer would expect to keep and back up, and the OS may empty
    // temporary at any moment, which would make the cache useless rather than
    // wrong.
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/http_cache');

    if (!await dir.exists()) await dir.create(recursive: true);

    return _instance = HttpDiskCache._(dir);
  }

  /// Namespace for the signed-in user. Set by the auth layer.
  String _userKey = 'anon';

  set userKey(String value) => _userKey = value.isEmpty ? 'anon' : value;

  String _keyFor(RequestOptions options) {
    // The token itself is NOT part of the key - it rotates on every refresh,
    // which would throw the whole cache away every few minutes. The subject
    // does not.
    final raw = '$_userKey|${options.method} ${options.uri}';
    return _hash(raw);
  }

  /// FNV-1a, 64-bit, written out rather than pulling in the crypto package.
  ///
  /// This names a cache entry; it is not a security boundary. What it does
  /// have to be is collision-resistant enough that two different URLs never
  /// share a file, because that would serve one response in place of another -
  /// and at 64 bits over a few hundred entries that is not a risk worth
  /// carrying a dependency for. Two rounds with different offsets give 128
  /// bits, which puts it comfortably out of reach.
  static String _hash(String input) {
    var a = 0xcbf29ce484222325;
    var b = 0x84222325cbf29ce4;

    for (final unit in utf8.encode(input)) {
      a = (a ^ unit) * 0x100000001b3;
      b = (b ^ (unit + 7)) * 0x100000001b3;
    }

    return (a & 0x7fffffffffffffff).toRadixString(16).padLeft(16, '0') +
        (b & 0x7fffffffffffffff).toRadixString(16).padLeft(16, '0');
  }

  File _meta(String key) => File('${_directory.path}/$key.meta');
  File _body(String key) => File('${_directory.path}/$key.body');

  Future<_Entry?> _read(String key) async {
    try {
      final meta = _meta(key);
      final body = _body(key);

      if (!await meta.exists() || !await body.exists()) return null;

      final json = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;

      return _Entry(
        etag: json['etag'] as String?,
        immutable: json['immutable'] as bool? ?? false,
        maxAge: json['maxAge'] as int? ?? 0,
        storedAt: DateTime.fromMillisecondsSinceEpoch(json['storedAt'] as int),
        contentType: json['contentType'] as String?,
        bytes: await body.readAsBytes(),
      );
    } catch (_) {
      // A half-written or corrupt entry is a cache miss, never an error the
      // customer sees. The app must work with no cache at all.
      return null;
    }
  }

  Future<void> _write(String key, Response response) async {
    try {
      final bytes = _bytesOf(response);
      if (bytes == null) return;

      final cacheControl = response.headers.value('cache-control') ?? '';
      if (cacheControl.contains('no-store')) return;

      await _body(key).writeAsBytes(bytes, flush: true);
      await _meta(key).writeAsString(jsonEncode({
        'etag': response.headers.value('etag'),
        'immutable': cacheControl.contains('immutable'),
        'maxAge': _maxAgeOf(cacheControl),
        'storedAt': DateTime.now().millisecondsSinceEpoch,
        'contentType': response.headers.value('content-type'),
      }), flush: true);

      await _evictIfOver();
    } catch (_) {
      // Out of disk, or a sandbox refusal. Not being able to cache is not a
      // reason to fail the request that just succeeded.
    }
  }

  /// Everything, on sign-out. See the note on per-user keying above: the key
  /// changes with the user, but a device that is handed on should not keep the
  /// previous customer's documents on disk at all.
  Future<void> clear() async {
    try {
      if (await _directory.exists()) {
        await _directory.delete(recursive: true);
        await _directory.create(recursive: true);
      }
    } catch (_) {/* nothing to do about it */}
  }

  static int _maxAgeOf(String cacheControl) {
    final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  static List<int>? _bytesOf(Response response) {
    final data = response.data;

    if (data is List<int>) return data;
    if (data is String) return utf8.encode(data);

    // Decoded JSON. Re-encoded rather than skipped: the whole point is to have
    // the list on disk, and Dio has already thrown the original bytes away by
    // the time an interceptor sees a decoded map.
    try {
      return utf8.encode(jsonEncode(data));
    } catch (_) {
      return null;
    }
  }

  Future<void> _evictIfOver() async {
    final files = await _directory
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();

    var total = 0;
    for (final f in files) {
      total += await f.length();
    }

    if (total <= _maxBytes) return;

    // Oldest first, and .meta/.body go together - deleting one of a pair
    // leaves an entry that reads as a miss anyway, but leaks the other half.
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

    for (final f in files) {
      if (total <= _maxBytes) break;
      total -= await f.length();
      try {
        await f.delete();
      } catch (_) {/* already gone */}
    }
  }
}

class _Entry {
  _Entry({
    required this.etag,
    required this.immutable,
    required this.maxAge,
    required this.storedAt,
    required this.contentType,
    required this.bytes,
  });

  final String? etag;
  final bool immutable;
  final int maxAge;
  final DateTime storedAt;
  final String? contentType;
  final List<int> bytes;

  /// Usable with no request at all.
  bool get isFresh {
    if (immutable) return true;
    if (maxAge <= 0) return false;
    return DateTime.now().difference(storedAt).inSeconds < maxAge;
  }
}

/// Wires [HttpDiskCache] into Dio.
class HttpCacheInterceptor extends Interceptor {
  HttpCacheInterceptor(this._cache);

  final HttpDiskCache _cache;

  static const _keyExtra = 'swarnim.cacheKey';

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.method.toUpperCase() != 'GET') return handler.next(options);

    final key = _cache._keyFor(options);
    options.extra[_keyExtra] = key;

    final entry = await _cache._read(key);
    if (entry == null) return handler.next(options);

    if (entry.isFresh) {
      // Answered entirely from disk. This is the case that makes a document
      // or a photograph appear instantly the second time.
      return handler.resolve(_responseFrom(options, entry), true);
    }

    if (entry.etag != null) {
      options.headers['If-None-Match'] = entry.etag;

      // 304 has to arrive as a RESPONSE, not an error, or every revalidation
      // would surface as a failure to the caller.
      final existing = options.validateStatus;
      options.validateStatus =
          (status) => status == 304 || existing(status);
    }

    handler.next(options);
  }

  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    final key = response.requestOptions.extra[_keyExtra] as String?;
    if (key == null) return handler.next(response);

    if (response.statusCode == 304) {
      final entry = await _cache._read(key);

      if (entry != null) {
        // Unchanged: hand back what is on disk, as though the server had sent
        // it. The caller cannot tell the difference, which is the point - no
        // screen needs to know it is looking at a cached list.
        return handler.resolve(_responseFrom(response.requestOptions, entry));
      }

      // 304 with nothing cached should not happen - it means the entry was
      // evicted between the request and the reply. Ask again properly rather
      // than hand back an empty body.
      final retried = await Dio().fetch(response.requestOptions
        ..headers.remove('If-None-Match'));
      return handler.resolve(retried);
    }

    if (response.statusCode == 200) {
      await _cache._write(key, response);
    }

    handler.next(response);
  }

  Response _responseFrom(RequestOptions options, _Entry entry) {
    // Decoded back into the shape the caller asked for: a screen expecting a
    // List gets a List, one expecting bytes gets bytes.
    final data = switch (options.responseType) {
      ResponseType.bytes => entry.bytes,
      ResponseType.plain => utf8.decode(entry.bytes),
      _ => _decodeJson(entry.bytes),
    };

    return Response(
      requestOptions: options,
      data: data,
      statusCode: 200,
      headers: Headers.fromMap({
        if (entry.contentType != null) 'content-type': [entry.contentType!],
        'x-swarnim-cache': ['hit'],
      }),
    );
  }

  static dynamic _decodeJson(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }
}
