import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'http_cache.dart';

/// Tokens live in the platform keystore (Android Keychain / iOS Keychain),
/// never in SharedPreferences - a refresh token is a 30-day credential.
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'swarnim.access_token';
  static const _refreshKey = 'swarnim.refresh_token';

  /// The unit ID or staff email this device signed in with. Kept beside the
  /// tokens so that a password change works on a session RESTORED from them,
  /// not only on one made minutes earlier in the same process - see
  /// [AuthController.setPassword].
  ///
  /// Not a secret in the way the tokens are: for a customer it is the unit ID
  /// printed on the allotment letter and shown in the app's own header, and
  /// for staff it is their work email. It is stored here rather than in plain
  /// preferences only because it belongs to the same lifecycle - cleared by
  /// the same [clear].
  static const _identifierKey = 'swarnim.identifier';

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);
  Future<String?> readIdentifier() => _storage.read(key: _identifierKey);

  Future<void> writeIdentifier(String identifier) =>
      _storage.write(key: _identifierKey, value: identifier);

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _identifierKey);
  }
}

final tokenStoreProvider = Provider<TokenStore>(
  // v10+ of the plugin encrypts on Android by default, so no options needed.
  (ref) => TokenStore(const FlutterSecureStorage()),
);

/// What the app knows about the signed-in session.
sealed class AuthState {
  const AuthState();
}

/// Before the stored tokens have been read - the splash state.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn({
    required this.displayName,
    required this.mustChangePassword,
    required this.isStaff,
    this.profileRequired = false,
  });

  final String displayName;

  /// Builder-issued passwords get printed on allotment letters and shared, so
  /// the first sign-in must force a change.
  final bool mustChangePassword;

  /// Which app the person gets. Read back from the server rather than inferred
  /// from which login form was used: the token is the authority on what the
  /// session actually is, and it survives a restart, where the form does not.
  final bool isStaff;

  /// The flat this login belongs to has no holder on record. The session can
  /// do nothing but say who the holder is - the server refuses every other
  /// customer endpoint until it has one.
  final bool profileRequired;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Deliberately not awaited: build() must be synchronous. The router shows
    // the splash state until this resolves.
    Future.microtask(restoreSession);
    return const AuthUnknown();
  }

  Dio get _dio => ref.read(dioProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  /// Called at startup. A stored refresh token is only proof of a session if
  /// the server still honours it - a resale or a password change may have
  /// revoked it while the app was closed.
  Future<void> restoreSession() async {
    final refresh = await _store.readRefreshToken();
    if (refresh == null) {
      state = const SignedOut();
      return;
    }

    final ok = await refreshSession();
    if (!ok) state = const SignedOut();
  }

  /// Signs in with a unit ID or a work email - the server resolves which.
  ///
  /// There is one sign-in because there is one login screen. Which app the
  /// person lands in is decided from the credential that matched, not from
  /// something they had to pick before typing their password.
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/api/v1/auth/login', data: {
        'identifier': identifier,
        'password': password,
      });

      // Remembered for the one job below: re-establishing the session
      // immediately after a password change. Written to storage as well as
      // held in memory, so that the change also works on a session restored
      // from disk - which is every session after the first launch.
      _lastIdentifier = identifier;
      await _store.writeIdentifier(identifier);

      await _applyTokens(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// The identifier used for the current sign-in, held for [setPassword].
  String? _lastIdentifier;

  /// Replaces the password on this login with one the customer chooses.
  ///
  /// This is the second half of the entry flow: the site office issues a
  /// generated password, the customer signs in with it once, and here they
  /// replace it with their own. Until they do, the password they are using is
  /// one somebody at the office could read off a list.
  ///
  /// The server revokes every session on a successful change - that is the
  /// point of changing a password - which would otherwise sign this device out
  /// the moment it succeeded. So it signs straight back in with the new
  /// password, which it has in hand. The customer sees a screen that saves and
  /// moves on; the tokens underneath are new.
  /// First-run setup for a flat with no holder: the customer's details and
  /// the password they choose, in one submit.
  ///
  /// One call because it is one screen. Splitting it would mean a customer
  /// could end up recorded as the holder of a flat while still signed in on
  /// the password printed on their letter - the server writes both together
  /// or neither.
  ///
  /// No re-sign-in afterwards, unlike [setPassword]: this returns a full token
  /// set of its own, because the flat now has a holder and the restricted
  /// token it was called with is revoked server-side.
  Future<void> completeSetup({
    required String fullName,
    required String mobile,
    String? email,
    String? newPassword,
  }) async {
    try {
      final response = await _dio.post('/api/v1/auth/claim-unit', data: {
        'fullName': fullName,
        'mobile': mobile,
        if (email != null && email.isNotEmpty) 'email': email,
        if (newPassword != null && newPassword.isNotEmpty) 'newPassword': newPassword,
      });

      _lastIdentifier ??= await _store.readIdentifier();
      await _applyTokens(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> setPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post('/api/v1/auth/change-password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } on DioException catch (e) {
      throw ApiException.from(e);
    }

    // Memory first, storage second. Storage covers the ordinary case - the
    // app was restarted at some point since signing in - and the null case
    // that remains is a session predating this being stored at all.
    final identifier = _lastIdentifier ?? await _store.readIdentifier();

    if (identifier == null) {
      // Nothing to sign back in with. The password IS changed, so say nothing
      // went wrong and let them sign in again with the one they just chose.
      await signOut();
      return;
    }

    await signIn(identifier: identifier, password: newPassword);
  }

  /// Returns whether the session is still valid. Used by the API client's 401
  /// handler as well as at startup.
  Future<bool> refreshSession() async {
    final refresh = await _store.readRefreshToken();
    if (refresh == null) return false;

    try {
      final response =
          await _dio.post('/api/v1/auth/refresh', data: {'refreshToken': refresh});
      await _applyTokens(response.data as Map<String, dynamic>);
      return true;
    } on DioException {
      // The server revoked it - including the reuse-detection case, where the
      // only safe response is to make the user sign in again.
      await _store.clear();
      state = const SignedOut();
      return false;
    }
  }

  Future<void> signOut() async {
    final refresh = await _store.readRefreshToken();

    // Best effort: the local session ends regardless of whether the server
    // could be reached, but telling it lets the refresh token be revoked.
    if (refresh != null) {
      try {
        await _dio.post('/api/v1/auth/logout', data: {'refreshToken': refresh});
      } on DioException {
        // Ignored on purpose - see above.
      }
    }

    await _store.clear();

    // The cached responses go with the session.
    //
    // Entries are namespaced per user, so the next person to sign in would not
    // READ these - but a phone that has been handed on should not still have
    // the previous customer's documents and complaint list sitting on disk at
    // all. Deleting on sign-out is the difference between "they cannot see it"
    // and "it is not there".
    try {
      (await HttpDiskCache.open()).clear();
    } catch (_) {
      // Signing out must not fail because a directory could not be emptied.
    }

    state = const SignedOut();
  }

  Future<void> _applyTokens(Map<String, dynamic> data) async {
    final access = data['accessToken'] as String;

    await _store.save(
      access: access,
      refresh: data['refreshToken'] as String,
    );

    // Namespace the disk cache to this user, so two customers sharing a phone
    // can never read each other's cached lists. Derived from the token's
    // subject rather than the token itself, which rotates every few minutes.
    try {
      (await HttpDiskCache.open()).userKey = _subjectOf(access);
    } catch (_) {
      // An unreadable token just means the cache stays in the 'anon'
      // namespace - safe, because that namespace is cleared on sign-out too.
    }

    state = SignedIn(
      displayName: data['displayName'] as String? ?? '',
      mustChangePassword: data['mustChangePassword'] as bool? ?? false,

      // Sign-in and refresh both report this, so a restored session knows
      // which app to open without a second round trip. Defaulting to the
      // customer app is the safe read: it is the narrower of the two, and the
      // staff endpoints would refuse the token anyway.
      isStaff: data['isStaff'] as bool? ?? false,

      // Reported by sign-in and by refresh, so the gate survives a restart and
      // lifts by itself if the office allots the flat in the meantime.
      profileRequired: data['profileRequired'] as bool? ?? false,
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The `sub` claim of a JWT, without verifying it.
///
/// Used only to namespace the on-device cache. Verification is the server's
/// job and happens on every request; reading the subject here is no more
/// trusted than reading the display name, and a forged value would only give
/// somebody a different cache directory on their own phone.
String _subjectOf(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return 'anon';

    // Base64url without padding, which is what JWT uses and what
    // base64.decode refuses.
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');

    final claims = jsonDecode(utf8.decode(base64.decode(payload)));

    // Both halves: two customers can share a subject id across kinds, and a
    // staff token and a customer token must never share a cache namespace.
    final kind = claims['swarnim:kind'] ?? 'unknown';
    final sub = claims['sub'] ?? 'unknown';

    return '$kind:$sub';
  } catch (_) {
    return 'anon';
  }
}
