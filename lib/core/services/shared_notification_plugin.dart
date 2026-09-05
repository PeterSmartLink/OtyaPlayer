// One FlutterLocalNotificationsPlugin shared by Otya's local notification
// owners so Android channel registration and tap handling stay centralized.
//
// Notification routing:
//   2000-2003 -> PushNotificationService (updates, downloads, announcements)
//   everything else -> NotificationService (tool/local notifications)
//
// Media playback notifications are owned by audio_service/MediaSession and do
// not go through this plugin.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'push_notification_service.dart';

final sharedNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _sharedPluginInitialized = false;

Future<void> initSharedNotificationsPlugin() async {
  if (_sharedPluginInitialized) return;
  const androidSettings =
      AndroidInitializationSettings('@drawable/ic_notification');
  await sharedNotificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings),
    onDidReceiveNotificationResponse: sharedNotificationRouter,
  );
  final android = sharedNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) {
    for (final channel in _androidChannels) {
      await android.createNotificationChannel(channel);
    }
  }
  _sharedPluginInitialized = true;

  final launch = await sharedNotificationsPlugin
      .getNotificationAppLaunchDetails();
  final response = launch?.notificationResponse;
  if (launch?.didNotificationLaunchApp == true && response != null) {
    sharedNotificationRouter(response);
  }
}

const _androidChannels = <AndroidNotificationChannel>[
  AndroidNotificationChannel(
    'otya_updates',
    'Otya — Updates',
    description: 'Important Otya product and security updates',
    importance: Importance.high,
  ),
  AndroidNotificationChannel(
    'otya_announcements',
    'Otya — Announcements',
    description: 'Useful Otya announcements and account notices',
    importance: Importance.defaultImportance,
  ),
  AndroidNotificationChannel(
    'com.otyaplayer.app.tools.progress',
    'Otya Tools — Progress',
    description: 'Silent progress for active media tools',
    importance: Importance.low,
  ),
  AndroidNotificationChannel(
    'com.otyaplayer.app.tools.complete',
    'Otya Tools — Complete',
    description: 'Alerts when an Otya media task finishes',
    importance: Importance.high,
  ),
  AndroidNotificationChannel(
    'com.otyaplayer.app.tools.error',
    'Otya Tools — Errors',
    description: 'Alerts when an Otya media task needs attention',
    importance: Importance.high,
  ),
];

void sharedNotificationRouter(NotificationResponse response) {
  final id = response.id ?? -1;
  if (id >= 2000 && id <= 2003) {
    PushNotificationService.instance.handleTap(response);
    return;
  }
  NotificationService.instance.handleTap(response);
}
