import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import 'shared_notification_plugin.dart';

/// Push/announcement notification owner for Otya.
///
/// Update notifications never download or install an APK inside the app. A tap
/// opens only an HTTPS destination on an official PeterSmart Link host in the
/// external browser, preserving the same Play-safe update contract as the
/// in-app update dialog.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const _chUpdates = 'otya_updates';
  static const _chAnnounce = 'otya_announcements';

  static const int idUpdate = 2000;
  static const int idAnnounce = 2003;

  static const _prefixUpdate = 'update:';
  static const _prefixUrl = 'url:';
  static const _officialHost = 'petersmartlink.com';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await initSharedNotificationsPlugin();
    _initialized = true;
    debugPrint('[PushNotificationService] Initialized.');
  }

  void handleTap(NotificationResponse response) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTap(response));
  }

  bool _isOfficialUpdateUri(Uri? uri) {
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == _officialHost || host.endsWith('.$_officialHost');
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    debugPrint('[PushNotif] tapped id=${response.id} payload=$payload');

    if (payload.startsWith(_prefixUpdate)) {
      final rawUrl = payload.substring(_prefixUpdate.length).trim();
      final uri = Uri.tryParse(rawUrl);
      if (_isOfficialUpdateUri(uri)) {
        launchUrl(uri!, mode: LaunchMode.externalApplication).ignore();
      } else if (rawUrl.isNotEmpty) {
        debugPrint('[PushNotif] blocked untrusted update URL.');
      }
      return;
    }

    if (!payload.startsWith(_prefixUrl)) return;
    final rawUrl = payload.substring(_prefixUrl.length);
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;

    if (uri.scheme == 'otya' && uri.host == 'app') {
      final route = _canonicalRoute(uri.path);
      if (route != null) {
        try {
          AppRouter.router.go(route);
        } catch (error) {
          debugPrint('[PushNotif] app route failed: $error');
        }
      }
      return;
    }

    if (_isOfficialUpdateUri(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
    } else {
      debugPrint('[PushNotif] blocked untrusted notification URL.');
    }
  }

  String? _canonicalRoute(String raw) {
    var route = raw.trim();
    if (route == '/ai') route = '/support';
    if (route == '/airdrop') route = '/transfer';
    if (route == '/home') route = '/';

    const allowed = {
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
    return allowed.contains(route) ? route : null;
  }

  Future<void> showUpdateNotification({
    required String version,
    required String releaseNotes,
    required String downloadUrl,
  }) async {
    if (!_initialized) await init();

    final uri = Uri.tryParse(downloadUrl);
    final safeUrl = _isOfficialUpdateUri(uri) ? uri!.toString() : '';
    if (downloadUrl.isNotEmpty && safeUrl.isEmpty) {
      debugPrint('[PushNotif] rejected untrusted update destination.');
    }

    final androidDetails = AndroidNotificationDetails(
      _chUpdates,
      'Otya — Updates',
      channelDescription: 'Alerts when a new Otya version is available',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(
        releaseNotes,
        contentTitle: 'Otya $version is available',
        summaryText: 'Tap to open the official update destination',
      ),
    );

    await sharedNotificationsPlugin.show(
      idUpdate,
      'Update available — v$version',
      releaseNotes,
      NotificationDetails(android: androidDetails),
      payload: safeUrl.isNotEmpty ? '$_prefixUpdate$safeUrl' : null,
    );
    debugPrint('[PushNotif] showUpdateNotification v$version');
  }

  Future<void> showAnnouncement({
    required String title,
    required String body,
    String? url,
  }) async {
    if (!_initialized) await init();

    final androidDetails = AndroidNotificationDetails(
      _chAnnounce,
      'Otya — Announcements',
      channelDescription: 'General announcements from Otya',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(body),
    );

    await sharedNotificationsPlugin.show(
      idAnnounce,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: url != null && url.isNotEmpty ? '$_prefixUrl$url' : null,
    );
    debugPrint('[PushNotif] showAnnouncement: $title');
  }

  /// Compatibility cleanup for older callers. Otya no longer owns an in-app
  /// update download progress notification.
  Future<void> dismissDownload() async {}
}
