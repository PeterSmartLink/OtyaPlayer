import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../widgets/update_dialog.dart';
import 'shared_notification_plugin.dart';

/// Push/announcement notification owner for Otya.
///
/// Update taps always recheck release metadata and open Otya's native update
/// dialog. Web URLs are reserved for ordinary announcements, never updates.
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
  static const _nativeUpdatePayload = '${_prefixUpdate}native';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await initSharedNotificationsPlugin();
    _initialized = true;
    debugPrint('[PushNotificationService] Initialized.');
  }

  void handleTap(NotificationResponse response) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTap(response));
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _isOfficialHttpsUri(Uri? uri) {
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == _officialHost || host.endsWith('.$_officialHost');
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (kDebugMode) {
      debugPrint('[PushNotif] tapped id=${response.id}');
    }

    // The suffix is intentionally ignored. This also migrates old update
    // notifications whose payload contained a website URL: tapping them now
    // opens the native updater rather than launching that URL.
    if (payload.startsWith(_prefixUpdate)) {
      final context = AppRouter.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        UpdateDialog.checkAndShow(context, forceCheck: true).ignore();
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

    if (_isOfficialHttpsUri(uri)) {
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
  }) async {
    if (!_initialized) await init();

    final hasReleaseNotes = releaseNotes.trim().isNotEmpty;
    final title = 'Otya $version is ready';
    final body = hasReleaseNotes
        ? 'New features and improvements are ready. Tap to update in Otya.'
        : 'A new Otya version is ready. Tap to update in Otya.';

    final androidDetails = AndroidNotificationDetails(
      _chUpdates,
      'Otya — Updates',
      channelDescription: 'Alerts when a new Otya version is available',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Official Otya update',
      ),
    );

    await sharedNotificationsPlugin.show(
      idUpdate,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: _nativeUpdatePayload,
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

  Future<void> dismissDownload() async {}
}
