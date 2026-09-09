import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

import 'remote_control_service.dart';

/// Build-time public Firebase client configuration.
///
/// The project/app identifiers below are public Firebase client metadata and
/// are pinned to OTYA's verified Android app so release builds cannot silently
/// drift to another Firebase project. The API key is still supplied at build
/// time. Privileged Firebase service-account credentials never belong in the
/// APK; they stay only on OTYA's server-side control plane.
abstract final class OtyaFirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:82776565585:android:085cf9b4eecb76e9535570',
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '82776565585',
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'otya-player',
  );

  static bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );
}

/// Single owner for Firebase client initialization and optional telemetry.
///
/// OTYA remains offline-first. This service is invoked only after runApp(),
/// never controls startup, and treats every Firebase failure as non-fatal.
class FirebasePlatformService {
  FirebasePlatformService._();
  static final FirebasePlatformService instance = FirebasePlatformService._();

  bool _firebaseReady = false;
  bool _appCheckReady = false;
  bool _remoteListenerAttached = false;

  bool get configured => OtyaFirebaseConfig.configured;
  bool get ready => _firebaseReady;

  Future<bool> ensureInitialized() async {
    if (_firebaseReady) return true;
    if (!Platform.isAndroid || !OtyaFirebaseConfig.configured) return false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: OtyaFirebaseConfig.options);
      }
      _firebaseReady = true;
      return true;
    } catch (e, st) {
      debugPrint('[Firebase] init skipped (non-fatal): $e\n$st');
      return false;
    }
  }

  Future<void> initOptionalServices() async {
    if (!await ensureInitialized()) return;
    if (!_remoteListenerAttached) {
      RemoteControlService.instance.addListener(_remotePolicyChanged);
      _remoteListenerAttached = true;
    }
    await _applyPolicy();
  }

  void _remotePolicyChanged() {
    unawaited(_applyPolicy());
  }

  Future<void> _applyPolicy() async {
    if (!await ensureInitialized()) return;
    final remote = RemoteControlService.instance;
    final appCheckEnabled = remote.featureEnabled(
      'firebaseAppCheck',
      fallback: true,
    );
    final analyticsEnabled = remote.featureEnabled(
      'firebaseAnalytics',
      fallback: true,
    );
    final performanceEnabled = remote.featureEnabled(
      'firebasePerformance',
      fallback: true,
    );

    if (appCheckEnabled && !_appCheckReady) {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider:
              kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        );
        _appCheckReady = true;
      } catch (e) {
        debugPrint('[Firebase:AppCheck] unavailable (non-fatal): $e');
      }
    }

    try {
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(analyticsEnabled);
    } catch (e) {
      debugPrint('[Firebase:Analytics] configuration failed: $e');
    }

    try {
      await FirebasePerformance.instance
          .setPerformanceCollectionEnabled(performanceEnabled);
    } catch (e) {
      debugPrint('[Firebase:Performance] configuration failed: $e');
    }
  }

  /// Returns a fresh App Check token for OTYA's custom Cloudflare backend.
  /// Null means attestation is unavailable; callers must follow the server's
  /// current enforcement policy rather than crashing or blocking local media.
  Future<String?> appCheckToken({bool forceRefresh = false}) async {
    if (!RemoteControlService.instance.featureEnabled(
      'firebaseAppCheck',
      fallback: true,
    )) {
      return null;
    }
    if (!await ensureInitialized()) return null;
    if (!_appCheckReady) {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider:
              kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        );
        _appCheckReady = true;
      } catch (_) {
        return null;
      }
    }
    try {
      return await FirebaseAppCheck.instance.getToken(forceRefresh);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[Firebase:AppCheck] token unavailable: ${e.runtimeType}',
        );
      }
      return null;
    }
  }

  Future<Map<String, String>> protectedHeaders({
    Map<String, String>? base,
  }) async {
    final headers = <String, String>{...?base};
    final token = await appCheckToken();
    if (token != null && token.isNotEmpty) {
      headers['X-Firebase-AppCheck'] = token;
    }
    return headers;
  }
}
