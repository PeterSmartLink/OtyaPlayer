// lib/core/services/crash_reporter.dart
//
// CrashReporter — captures Flutter and platform errors, stores them locally
// when offline, and uploads them to /api/crash-report when online.
//
// Fire-and-forget safe: all errors are caught and logged, never thrown.
// Repeating framework errors are deduplicated so one bad frame cannot flood
// telemetry, email alerts, D1, or the network with hundreds of identical rows.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/environment.dart';
import 'api_signer.dart';
import 'device_service.dart';
import 'firebase_platform_service.dart';

class CrashReporter {
  CrashReporter._();
  static final CrashReporter instance = CrashReporter._();

  static const String _kPendingCrashes = 'otya_pending_crashes';
  static const int _maxStoredCrashes = 20;
  static const int _maxReportsPerSession = 30;
  static const Duration _duplicateWindow = Duration(minutes: 2);
  static const Duration _fingerprintRetention = Duration(minutes: 10);

  final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};
  final Set<String> _uploadsInFlight = <String>{};
  int _sessionReportCount = 0;

  Future<void> init() async {
    debugPrint('[CrashReporter] Initialising error handlers…');
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      recordCrash(
        'FlutterError',
        details.exceptionAsString(),
        details.stack,
      ).ignore();
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      recordCrash('PlatformError', error.toString(), stack).ignore();
      if (previousPlatformHandler != null) {
        return previousPlatformHandler(error, stack);
      }
      return true;
    };

    debugPrint('[CrashReporter] Error handlers installed.');
    unawaited(_uploadPendingCrashes());
  }

  Future<void> recordCrash(
    String errorType,
    String description,
    StackTrace? stack,
  ) async {
    try {
      final now = DateTime.now();
      final fingerprint = _fingerprint(errorType, description, stack);
      _pruneFingerprints(now);

      final previous = _recentFingerprints[fingerprint];
      if (previous != null && now.difference(previous) < _duplicateWindow) {
        debugPrint('[CrashReporter] Suppressed duplicate $errorType.');
        return;
      }
      if (_sessionReportCount >= _maxReportsPerSession) {
        debugPrint('[CrashReporter] Session telemetry cap reached.');
        return;
      }

      // Reserve the fingerprint before awaiting platform services. Multiple
      // framework callbacks can arrive in the same frame.
      _recentFingerprints[fingerprint] = now;
      _sessionReportCount += 1;

      final deviceId = await DeviceService.instance.getDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      final safeDescription = _sanitizeTelemetry(description);
      final safeStack = stack == null
          ? ''
          : _sanitizeTelemetry(stack.toString());
      final crash = <String, dynamic>{
        'device_id': deviceId,
        'app_version': packageInfo.version,
        'version_code': int.tryParse(packageInfo.buildNumber) ?? 0,
        'error_type': errorType,
        'description': safeDescription.length > 500
            ? safeDescription.substring(0, 500)
            : safeDescription,
        'stack_trace': safeStack.length > 1000
            ? safeStack.substring(0, 1000)
            : safeStack,
        'timestamp': now.toIso8601String(),
      };
      await _appendToPending(crash);
      unawaited(_uploadSingle(crash));
    } catch (e) {
      debugPrint('[CrashReporter] recordCrash internal error (non-fatal): $e');
    }
  }

  static Future<void> reportManual(String errorType, String description) async {
    await CrashReporter.instance.recordCrash(errorType, description, null);
  }

  /// Crash text can include HTTP headers, URLs, form values, or user paths.
  /// Redact common credentials and direct identifiers before the report is
  /// persisted to SharedPreferences as well as before it reaches the server.
  String _sanitizeTelemetry(String value) {
    var sanitized = value.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer <redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
      '<redacted-jwt>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        caseSensitive: false,
      ),
      '<redacted-email>',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'''(["']?(?:access_token|refresh_token|id_token|password|api_key)["']?\s*[:=]\s*)["']?[^\s,"'}&]+''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
    return sanitized.replaceAllMapped(
      RegExp(
        r'([?&](?:token|key|code|secret|password)=)[^&#\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
  }

  void report(Object error, StackTrace stack) {
    recordCrash(error.runtimeType.toString(), error.toString(), stack).ignore();
  }

  void _pruneFingerprints(DateTime now) {
    _recentFingerprints.removeWhere(
      (_, seenAt) => now.difference(seenAt) >= _fingerprintRetention,
    );
  }

  String _fingerprint(
    String errorType,
    String description,
    StackTrace? stack,
  ) {
    String normalize(String value) => value
        .replaceAll(RegExp(r'0x[0-9a-fA-F]+'), '<addr>')
        .replaceAll(RegExp(r'\b\d{5,}\b'), '<n>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final stackLines = stack
            ?.toString()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .take(3)
            .join(' ') ??
        '';
    return '${normalize(errorType)}|${normalize(description)}|${normalize(stackLines)}';
  }

  String _fingerprintFromCrash(Map<String, dynamic> crash) {
    final stackText = (crash['stack_trace'] as String?) ?? '';
    return _fingerprint(
      (crash['error_type'] as String?) ?? 'Unknown',
      (crash['description'] as String?) ?? '',
      stackText.isEmpty ? null : StackTrace.fromString(stackText),
    );
  }

  Future<void> _appendToPending(Map<String, dynamic> crash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _loadPendingFromPrefs(prefs)..add(crash);
      final trimmed = existing.length > _maxStoredCrashes
          ? existing.sublist(existing.length - _maxStoredCrashes)
          : existing;
      await prefs.setString(_kPendingCrashes, jsonEncode(trimmed));
    } catch (e) {
      debugPrint('[CrashReporter] _appendToPending error (non-fatal): $e');
    }
  }

  Future<void> _removeFromPending(Map<String, dynamic> crash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _loadPendingFromPrefs(prefs);
      existing.removeWhere((c) => c['timestamp'] == crash['timestamp']);
      await prefs.setString(_kPendingCrashes, jsonEncode(existing));
    } catch (e) {
      debugPrint('[CrashReporter] _removeFromPending error (non-fatal): $e');
    }
  }

  List<Map<String, dynamic>> _loadPendingFromPrefs(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_kPendingCrashes);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _uploadSingle(Map<String, dynamic> crash) async {
    final uploadKey = (crash['timestamp'] as String?) ?? jsonEncode(crash);
    if (!_uploadsInFlight.add(uploadKey)) return;

    try {
      const path = '/api/crash-report';
      final deviceId = (crash['device_id'] as String?) ?? '';
      final headers = await FirebasePlatformService.instance.protectedHeaders(
        base: {
          ...ApiSigner.signedHeaders(
            method: 'POST',
            path: path,
            deviceId: deviceId,
          ),
          'Content-Type': 'application/json',
        },
      );
      final response = await http
          .post(
            Uri.parse('${Environment.workerUrl}$path'),
            headers: headers,
            body: jsonEncode(crash),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _removeFromPending(crash);
      }
    } catch (e) {
      debugPrint('[CrashReporter] _uploadSingle error (non-fatal): $e');
    } finally {
      _uploadsInFlight.remove(uploadKey);
    }
  }

  Future<void> _uploadPendingCrashes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = _loadPendingFromPrefs(prefs);
      final seen = <String>{};
      for (final crash in pending) {
        final fingerprint = _fingerprintFromCrash(crash);
        if (!seen.add(fingerprint)) {
          // Keep one representative report, discard duplicate offline copies.
          await _removeFromPending(crash);
          continue;
        }
        await _uploadSingle(crash);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      debugPrint('[CrashReporter] _uploadPendingCrashes error (non-fatal): $e');
    }
  }
}
