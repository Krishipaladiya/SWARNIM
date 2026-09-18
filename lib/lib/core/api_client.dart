import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'http_cache.dart';

/// Where the app talks to.
///
/// A RELEASE build points at the live server by default, and a debug build at
/// the Android emulator's alias for the host machine. That split is the point:
/// the old default was the dev machine for every build, so a plain
/// `flutter build apk --release` shipped an app that could only work on the
/// laptop that built it - and it failed silently, as a network timeout on the
/// login screen, with nothing to say why.
///
/// --dart-define=API_BASE_URL=... still overrides both, which is how CI and a
/// staging build pick their own host:
///   flutter build apk --release --dart-define=API_BASE_URL=https://staging...
///
/// The debug host differs by platform because the two simulators disagree
/// about what "the machine I am running on" means: the Android emulator is a
/// separate device that reaches the host at 10.0.2.2, while the iOS simulator
/// shares the Mac's network and reaches it at localhost.
abstract final class AppConfig {
  /// Admin Central serves the portal and this API from one deployment.
  ///
  /// A name CloudVerve controls, deliberately, rather than the SmarterASP
  /// temp host it resolves to. Once this is in the App Store the value is
  /// frozen until the next release passes review, so it has to be a name that
  /// can be repointed at a new server by editing DNS instead of by shipping
  /// an app update.
  static const _live = 'https://swarnim.cloudverve.in';

  /// The server's own SmarterASP address. Still works, and is the override to
  /// build with if the name above is ever not answering.
  // ignore: unused_field
  static const _liveDirect = 'https://dhwanipaladiya-001-site1.dtempurl.com';

  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl =>
      _override != '' ? _override : (kReleaseMode ? _live : _debugHost);

  /// Android emulator: 10.0.2.2 is the host machine, and localhost is the
  /// emulator itself. iOS simulator: the other way round - it shares the Mac's
  /// network, and 10.0.2.2 is nothing at all.
  static String get _debugHost =>
      Platform.isAndroid ? 'http://10.0.2.2:5217' : 'http://localhost:5217';
}

/// An error the user can actually be shown.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorised => statusCode == 401;

  /// The API returns RFC 9110 problem documents, so the useful sentence is in
  /// `detail`. Falling back to a raw Dio message would show the customer a
  /// stack-trace-flavoured string.
  factory ApiException.from(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;

    if (data is Map && data['detail'] is String) {
      return ApiException(data['detail'] as String, statusCode: status);
    }

    final message = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The server took too long to respond. Please try again.',
      DioExceptionType.connectionError =>
        'Cannot reach the server. Check your connection.',
      _ when status == 429 =>
        'Too many attempts. Please wait a minute and try again.',
      _ when status != null && status >= 500 =>
        'Something went wrong at our end. Please try again shortly.',
      _ => 'Something went wrong. Please try again.',
    };

    return ApiException(message, statusCode: status);
  }

  @override
  String toString() => message;
}

/// Attaches the access token, and transparently refreshes it once on a 401.
///
/// The single-flight guard matters: a screen that fires four requests on load
/// would otherwise trigger four parallel refreshes, and because the server
/// rotates refresh tokens, three of them would be rejected as *reuse* - which
/// revokes the whole chain and signs the user out. That bug is very hard to
/// reproduce and very easy to prevent here.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._ref, this._dio);

  final Ref _ref;
  final Dio _dio;
  Future<bool>? _inFlightRefresh;

  static const _retriedFlag = 'swarnim_retried';

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _ref.read(tokenStoreProvider).readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final isAuthCall = request.path.startsWith('/api/v1/auth/');

    // Never retry the auth endpoints themselves: a failed sign-in is a real
    // answer, and retrying a refresh would loop.
    if (err.response?.statusCode != 401 ||
        isAuthCall ||
        request.extra[_retriedFlag] == true) {
      return handler.next(err);
    }

    final refreshed = await (_inFlightRefresh ??= _refresh());

    if (!refreshed) return handler.next(err);

    try {
      request.extra[_retriedFlag] = true;
      final response = await _dio.fetch(request);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refresh() async {
    try {
      return await _ref.read(authControllerProvider.notifier).refreshSession();
    } finally {
      _inFlightRefresh = null;
    }
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    contentType: 'application/json',
    // Let the interceptor see 401s rather than Dio throwing before it runs.
    validateStatus: (status) => status != null && status < 400,
  ));

  dio.interceptors.add(_AuthInterceptor(ref, dio));

  // The disk cache goes AFTER the auth interceptor, deliberately.
  //
  // Dio runs request interceptors in order, so auth attaches the bearer token
  // first and the cache sees a fully formed request; and on the way back the
  // cache sees the response before auth would retry it. The other order would
  // mean a cached hit short-circuiting before the token was attached, which
  // works by accident until the first 401 refresh.
  //
  // Opened asynchronously and attached when ready: the provider is
  // synchronous, and blocking app start on a directory lookup to save a few
  // kilobytes would be the wrong trade. Requests made in the first
  // milliseconds simply go to the network, as they did before.
  HttpDiskCache.open().then((cache) {
    dio.interceptors.add(HttpCacheInterceptor(cache));
  });

  return dio;
});
