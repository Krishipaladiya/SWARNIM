import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// Tokens live in the platform keystore (Android Keychain / iOS Keychain),
/// never in SharedPreferences - a refresh token is a 30-day credential.
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'swarnim.access_token';
  static const _refreshKey = 'swarnim.refresh_token';

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
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
  });

  final String displayName;

  /// Builder-issued passwords get printed on allotment letters and shared, so
  /// the first sign-in must force a change.
  final bool mustChangePassword;

  /// Which app the person gets. Read back from the server rather than inferred
  /// from which login form was used: the token is the authority on what the
  /// session actually is, and it survives a restart, where the form does not.
  final bool isStaff;
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
      await _applyTokens(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
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
    state = const SignedOut();
  }

  Future<void> _applyTokens(Map<String, dynamic> data) async {
    await _store.save(
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
    );

    state = SignedIn(
      displayName: data['displayName'] as String? ?? '',
      mustChangePassword: data['mustChangePassword'] as bool? ?? false,

      // Sign-in and refresh both report this, so a restored session knows
      // which app to open without a second round trip. Defaulting to the
      // customer app is the safe read: it is the narrower of the two, and the
      // staff endpoints would refuse the token anyway.
      isStaff: data['isStaff'] as bool? ?? false,
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
