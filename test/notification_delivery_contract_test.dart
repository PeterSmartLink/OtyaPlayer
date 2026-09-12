import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background update taps use the foreground in-app update handler', () {
    final source = File('lib/core/services/fcm_service.dart').readAsStringSync();
    final opened = source.substring(source.indexOf('Future<void> _handleOpenedMessage'));
    final update = opened.substring(0, opened.indexOf('final route ='));
    expect(update, contains("message.data['type']?.toString() == 'update'"));
    expect(update, contains('PushNotificationService.instance.handleTap'));
    expect(update, contains('id: PushNotificationService.idUpdate'));
    expect(update, contains('return;'));
    expect(update, isNot(contains('launchUrl')));
  });

  test('notification startup coalesces concurrent callers', () {
    final source = File('lib/core/services/shared_notification_plugin.dart')
        .readAsStringSync();
    expect(source, contains('final existing = _sharedPluginInit'));
    expect(source, contains('if (existing != null) return existing'));
    expect(source, contains('identical(_sharedPluginInit, attempt)'));
  });

  test('notification taps schedule a frame even while the UI is idle', () {
    for (final path in [
      'lib/core/services/notification_service.dart',
      'lib/core/services/push_notification_service.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('ensureVisualUpdate()'));
    }
  });
  test('ordinary notification channels exist before background delivery', () {
    final source = File(
      'lib/core/services/shared_notification_plugin.dart',
    ).readAsStringSync();

    expect(source, contains('createNotificationChannel'));
    expect(source, contains("'otya_updates'"));
    expect(source, contains("'otya_announcements'"));
    expect(source, contains('getNotificationAppLaunchDetails'));
    expect(source, contains('didNotificationLaunchApp'));
  });

  test('ordinary notification permission remains user-driven', () {
    final fcm = File('lib/core/services/fcm_service.dart').readAsStringSync();
    final settings = File(
      'lib/features/settings/presentation/settings_detail_screen.dart',
    ).readAsStringSync();

    expect(fcm, isNot(contains('messaging.requestPermission')));
    expect(fcm, isNot(contains('_ensureNotificationPermission')));
    expect(settings, contains("title: 'Notifications'"));
    expect(
      settings,
      contains('NotificationService.instance.requestPermission()'),
    );

    final notificationStart = settings.indexOf("title: 'Notifications'");
    final notificationEnd = settings.indexOf("title: 'Android app permissions'");
    expect(notificationStart, greaterThanOrEqualTo(0));
    expect(notificationEnd, greaterThan(notificationStart));
    final notificationTile = settings.substring(notificationStart, notificationEnd);
    expect(notificationTile, contains("label: 'Open settings'"));
    expect(notificationTile, contains('openAppSettings()'));
    expect(notificationTile, contains('action: granted'));
  });

  test('existing installs receive one non-repeating notification prompt', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    final notifications = File(
      'lib/core/services/notification_service.dart',
    ).readAsStringSync();

    expect(app, contains('requestPermissionOnce()'));
    expect(
      notifications,
      contains('notification_permission_prompted_v1'),
    );
    expect(
      notifications,
      contains('if (prefs.getBool(_permissionPromptKey) == true) return null'),
    );
    expect(notifications, contains('prefs.setBool(_permissionPromptKey, true)'));
  });

  test('remote notification links are limited to official HTTPS hosts', () {
    final fcm = File('lib/core/services/fcm_service.dart').readAsStringSync();
    final push = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(fcm, contains("uri.scheme != 'https'"));
    expect(fcm, isNot(contains("{'https', 'http'}")));
    expect(push, contains("host.endsWith('.\$_officialHost')"));
    expect(push, contains('blocked untrusted notification URL'));
  });
}
