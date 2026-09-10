import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';

/// Build-time configuration.
///
/// Pass a real host with:
///   flutter run --dart-define=API_BASE_URL=https://api.swarnim.in
///
/// The default is the Android emulator's alias for the host machine - localhost
/// inside the emulator is the emulator itself, which is the single most common
/// "why can't the app reach my API" mistake.
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5199',
  );
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
  return dio;
});
