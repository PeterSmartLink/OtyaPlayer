// lib/core/services/http_client.dart
//
// A single persistent HTTP client reused across all API calls.
// This keeps TCP/TLS connections alive (HTTP Keep-Alive) so each
// subsequent request skips the handshake — much faster on mobile.
//
// Security: abuse-sensitive OTYA Cloudflare requests automatically receive
// Firebase App Check attestation when available. Attestation is best-effort
// and never blocks local/offline media behavior.
//
// Retry policy: up to 2 retries for 5xx responses and network errors,
// with 1 s backoff after the first failure and 2 s after the second.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/environment.dart';
import 'firebase_platform_service.dart';

class AppHttpClient {
  AppHttpClient._();
  static final AppHttpClient instance = AppHttpClient._();

  // Persistent client — do NOT create a new one per request.
  final http.Client _innerClient = http.Client();
  late final http.Client _client = _OtyaProtectedClient(_innerClient);

  http.Client get client => _client;

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 30);
  static const int _maxRetries = 2;
  static const List<Duration> _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// Returns true for status codes that should trigger a retry.
  static bool _isRetryableStatus(int statusCode) =>
      statusCode >= 500 && statusCode < 600;

  /// Returns true for exceptions that should trigger a retry.
  static bool _isRetryableException(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException;

  /// Convenience: GET with connect + receive timeouts and retry.
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = _receiveTimeout,
  }) =>
      _withRetry(() => _client.get(uri, headers: headers).timeout(timeout));

  /// Convenience: POST with connect + receive timeouts and retry.
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _receiveTimeout,
  }) =>
      _withRetry(
        () => _client.post(uri, headers: headers, body: body).timeout(timeout),
      );

  /// Convenience: PATCH with connect + receive timeouts and retry.
  Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _receiveTimeout,
  }) =>
      _withRetry(
        () => _client.patch(uri, headers: headers, body: body).timeout(timeout),
      );

  /// Executes [request] with up to [_maxRetries] retries on 5xx or network
  /// errors. Uses exponential-ish backoff: 1 s, then 2 s.
  Future<http.Response> _withRetry(
    Future<http.Response> Function() request,
  ) async {
    int attempt = 0;
    while (true) {
      try {
        final response = await request().timeout(_connectTimeout);
        if (_isRetryableStatus(response.statusCode) &&
            attempt < _maxRetries) {
          debugPrint(
            '[AppHttpClient] ${response.statusCode} — retrying '
            '(attempt ${attempt + 1}/$_maxRetries)…',
          );
          await Future<void>.delayed(_retryDelays[attempt]);
          attempt++;
          continue;
        }
        return response;
      } catch (e) {
        if (_isRetryableException(e) && attempt < _maxRetries) {
          debugPrint(
            '[AppHttpClient] Network error (${e.runtimeType}) — retrying '
            '(attempt ${attempt + 1}/$_maxRetries)…',
          );
          await Future<void>.delayed(_retryDelays[attempt]);
          attempt++;
          continue;
        }
        rethrow;
      }
    }
  }

  void dispose() => _client.close();
}

/// Adds App Check only to endpoints where forged clients create meaningful
/// abuse risk. Public release/config/theme endpoints stay fast and cacheable.
class _OtyaProtectedClient extends http.BaseClient {
  _OtyaProtectedClient(this._inner);

  final http.Client _inner;

  static const _protectedPrefixes = <String>[
    '/auth/',
    '/api/ai',
    '/api/support',
    '/api/feedback',
    '/api/device',
    '/api/devices',
    '/api/account',
    '/api/together',
  ];

  static bool _shouldAttest(Uri uri) {
    // Never send an App Check token to an arbitrary HTTPS host that happens to
    // use one of Otya's protected path names. The shared HTTP client is exposed
    // to the rest of the app, so origin pinning is the final credential guard.
    final workerUri = Uri.tryParse(Environment.workerUrl);
    if (workerUri == null || workerUri.scheme != 'https') return false;
    if (uri.scheme != workerUri.scheme ||
        uri.host.toLowerCase() != workerUri.host.toLowerCase() ||
        uri.port != workerUri.port) {
      return false;
    }
    return _protectedPrefixes.any(uri.path.startsWith);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_shouldAttest(request.url) &&
        !request.headers.containsKey('X-Firebase-AppCheck')) {
      try {
        final token = await FirebasePlatformService.instance.appCheckToken();
        if (token != null && token.isNotEmpty) {
          request.headers['X-Firebase-AppCheck'] = token;
        }
      } catch (e) {
        // App Check is deliberately non-fatal until the server policy says
        // enforcement is safe. Local playback is never coupled to this path.
        debugPrint('[AppHttpClient] App Check unavailable: ${e.runtimeType}');
      }
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
