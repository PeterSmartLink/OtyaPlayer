import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../config/environment.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'firebase_platform_service.dart';
import 'push_notification_service.dart';

@pragma('vm:entry-point')
Future<void> otyaFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await FirebasePlatformService.instance.ensureInitialized();
  } catch (e) {
    debugPrint('[FCM:bg] Firebase init skipped: $e');
  }
  debugPrint('[FCM:bg] message=${message.messageId}');
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const _keyFcmToken = 'fcm_token';
  static const _publicTopic = 'otya_public';
  bool _initialized = false;
  bool _listenersAttached = false;
  Future<void>? _initInFlight;

  static const Set<String> _allowedRoutes = {
    '/',
    '/music',
    '/myspace',
    '/support',
    '/transfer',
    '/downloads',
    '/settings',
    '/settings/storage',
    '/profile',
    '/about',
    '/privacy',
    '/whats-new',
    '/playlists',
    '/history',
  };

  Future<void> init() async {
    if (_initialized) return;
    final existing = _initInFlight;
    if (existing != null) return existing;

    final attempt = _initOnce();
    _initInFlight = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_initInFlight, attempt)) _initInFlight = null;
    }
  }

  Future<void> _initOnce() async {
    if (!Platform.isAndroid) {
      debugPrint('[FCM] Android transport not required on this platform.');
      _initialized = true;
      return;
    }
    if (!OtyaFirebaseConfig.configured) {
      debugPrint('[FCM] Disabled: Firebase build configuration is incomplete.');
      _initialized = true;
      return;
    }

    try {
      if (!await FirebasePlatformService.instance.ensureInitialized()) return;

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);

      if (!_listenersAttached) {
        FirebaseMessaging.onBackgroundMessage(otyaFirebaseBackgroundHandler);
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
        messaging.onTokenRefresh.listen((token) {
          _storeAndRegister(token).ignore();
          _syncPublicTopic(messaging).ignore();
        });
        _listenersAttached = true;
      }

      _initialized = true;

      await _syncPublicTopic(messaging);

      try {
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          await _handleOpenedMessage(initialMessage);
        }
      } catch (e) {
        debugPrint('[FCM] initial message lookup failed (non-fatal): $e');
      }

      try {
        final token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _storeAndRegister(token);
        } else {
          final prefs = await SharedPreferences.getInstance();
          final cached = prefs.getString(_keyFcmToken);
          if (cached != null && cached.isNotEmpty) {
            await _registerWithBackend(cached);
          }
        }
      } catch (e) {
        debugPrint('[FCM] initial token sync failed (non-fatal): $e');
      }

      debugPrint('[FCM] Initialized and token sync requested.');
    } catch (e, st) {
      debugPrint('[FCM] init error (non-fatal): $e\n$st');
    }
  }

  Future<void> _syncPublicTopic(FirebaseMessaging messaging) async {
    try {
      await messaging.subscribeToTopic(_publicTopic);
    } catch (e) {
      debugPrint('[FCM] public topic sync failed (non-fatal): $e');
    }
  }

  Future<void> syncRegistration() async {
    if (!OtyaFirebaseConfig.configured || !Platform.isAndroid) return;
    try {
      if (!await FirebasePlatformService.instance.ensureInitialized()) return;
      final messaging = FirebaseMessaging.instance;
      await _syncPublicTopic(messaging);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_keyFcmToken) ?? await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _storeAndRegister(token);
      }
    } catch (e) {
      debugPrint('[FCM] registration sync failed (non-fatal): $e');
    }
  }

  Future<void> _storeAndRegister(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFcmToken, token);
    await _registerWithBackend(token);
  }

  Future<void> _registerWithBackend(String token) async {
    try {
      final deviceId = await DeviceService.instance.getDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      final accessToken = await AuthService.instance.getValidToken();
      final headers = await FirebasePlatformService.instance.protectedHeaders(
        base: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (accessToken != null && accessToken.isNotEmpty)
            'Authorization': 'Bearer $accessToken',
        },
      );

      final response = await http
          .post(
            Uri.parse(Environment.apiDeviceUrl),
            headers: headers,
            body: jsonEncode({
              'device_id': deviceId,
              'app_version': packageInfo.version,
              'app_build': int.tryParse(packageInfo.buildNumber) ?? 0,
              'arch': Environment.appArch,
              'platform': 'android',
              'locale': Platform.localeName,
              'fcm_token': token,
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[FCM] device token registration → ${response.statusCode}');
    } catch (e) {
      debugPrint('[FCM] backend registration failed (non-fatal): $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null || title.isEmpty || body == null || body.isEmpty) return;

    final type = message.data['type']?.toString();
    if (type == 'update') {
      final version = message.data['version']?.toString();
      if (version != null && version.isNotEmpty) {
        await PushNotificationService.instance.showUpdateNotification(
          version: version,
          releaseNotes: body,
        );
        return;
      }
    }

    await PushNotificationService.instance.showAnnouncement(
      title: title,
      body: body,
      url: _notificationTarget(message),
    );
  }

  String? _notificationTarget(RemoteMessage message) {
    final route = _canonicalRoute(message.data['route']?.toString());
    if (route != null) return 'otya://app$route';
    return message.data['url']?.toString();
  }

  String? _canonicalRoute(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var route = raw.trim();

    if (route == '/ai') route = '/support';
    if (route == '/airdrop') route = '/transfer';
    if (route == '/home') route = '/';

    return _allowedRoutes.contains(route) ? route : null;
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    // Update pushes never trust or open a server-provided URL. The app rechecks
    // canonical release metadata, then uses the native in-app updater.
    if (message.data['type']?.toString() == 'update') {
      PushNotificationService.instance.handleTap(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: PushNotificationService.idUpdate,
        payload: 'update:native',
      ));
      return;
    }

    final route = _canonicalRoute(message.data['route']?.toString());
    if (route != null) {
      try {
        AppRouter.router.go(route);
        return;
      } catch (e) {
        debugPrint('[FCM] in-app notification route failed: $e');
      }
    }

    final rawUrl = message.data['download_url']?.toString() ??
        message.data['url']?.toString();
    if (rawUrl == null || rawUrl.isEmpty) return;

    final appUri = Uri.tryParse(rawUrl);
    if (appUri != null && appUri.scheme == 'otya' && appUri.host == 'app') {
      final appRoute = _canonicalRoute(appUri.path);
      if (appRoute != null) {
        try {
          AppRouter.router.go(appRoute);
        } catch (e) {
          debugPrint('[FCM] OTYA URI route failed: $e');
        }
      }
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !_isOfficialHttpsUri(uri)) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[FCM] notification URL open failed: $e');
    }
  }

  bool _isOfficialHttpsUri(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'petersmartlink.com' ||
        host.endsWith('.petersmartlink.com');
  }
}
