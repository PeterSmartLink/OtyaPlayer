import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('critical playback and New Way runtime are never debug-only', () {
    const criticalPaths = <String>[
      'lib/main.dart',
      'lib/core/services/audio_handler.dart',
      'lib/core/services/media_notification_service.dart',
      'lib/features/transfer/data/transfer_hotspot_service.dart',
    ];

    for (final path in criticalPaths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('kDebugMode')),
        reason: '$path must not hide a production feature behind kDebugMode.',
      );
      expect(
        source,
        isNot(contains('kReleaseMode')),
        reason: '$path must not fork feature behavior by Flutter build mode.',
      );
    }
  });

  test('debug and every publication path share one Android runtime config', () {
    final debug = File('.github/workflows/test-apk.yml').readAsStringSync();
    final validation = File('.github/workflows/release-mode-validation.yml')
        .readAsStringSync();
    final direct =
        File('.github/workflows/release-apk.yml').readAsStringSync();
    final play =
        File('.github/workflows/play-closed-test.yml').readAsStringSync();
    final release = File('.github/workflows/release.yml').readAsStringSync();
    final shared = File('scripts/android-release-config.sh').readAsStringSync();

    for (final workflow in [debug, validation, direct, play, release]) {
      expect(
        workflow,
        contains('scripts/android-release-config.sh'),
        reason: 'Android workflows must not maintain private copies of Firebase/Google runtime defines.',
      );
    }

    expect(debug, contains("OTYA_SELF_UPDATE: 'true'"));
    expect(validation, contains("OTYA_SELF_UPDATE: 'true'"));
    expect(direct, contains("OTYA_SELF_UPDATE: 'true'"));
    expect(play, contains("OTYA_SELF_UPDATE: 'false'"));
    expect(release, contains('configure_otya_release_defines true'));
    expect(release, contains('configure_otya_release_defines false'));

    expect(shared, contains('FIREBASE_API_KEY'));
    expect(shared, contains('GOOGLE_WEB_CLIENT_ID'));
    expect(shared, contains('FIREBASE_APP_ID'));
    expect(shared, contains('FIREBASE_MESSAGING_SENDER_ID'));
    expect(shared, contains('FIREBASE_PROJECT_ID'));
  });

  test('publishable APK paths verify the compiled release binary', () {
    final validation = File('.github/workflows/release-mode-validation.yml')
        .readAsStringSync();
    final direct =
        File('.github/workflows/release-apk.yml').readAsStringSync();
    final release = File('.github/workflows/release.yml').readAsStringSync();
    final verifier =
        File('scripts/verify-android-release-apk.sh').readAsStringSync();

    for (final workflow in [validation, direct, release]) {
      expect(workflow, contains('verify-android-release-apk.sh'));
    }

    expect(verifier, contains('manifest debuggable'));
    expect(verifier, contains('AudioService'));
    expect(verifier, contains('MediaButtonReceiver'));
    expect(verifier, contains('FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    expect(verifier, contains('POST_NOTIFICATIONS'));
    expect(verifier, contains('NEARBY_WIFI_DEVICES'));
    expect(verifier, contains('OtyaTransferAndroidPlugin'));
    expect(verifier, contains('dex packages --defined-only'));
  });

  test('Now Playing retries a failed Android media-session startup', () {
    final main = File('lib/main.dart').readAsStringSync();
    final handler =
        File('lib/core/services/audio_handler.dart').readAsStringSync();
    final notification =
        File('lib/core/services/media_notification_service.dart')
            .readAsStringSync();

    expect(
      main,
      contains('configureEnsureReady(_ensurePlaybackPlatform)'),
      reason: 'The playback service needs a process-level recovery entry point.',
    );
    expect(main, contains('Future<void> _ensurePlaybackPlatform()'));
    expect(main, contains('_playbackPlatformInit'));
    expect(handler, contains('Future<bool> ensureReady() async'));
    expect(handler, contains('_ensureReadyFuture'));
    expect(notification, contains('AudioHandlerSingleton.instance.ensureReady()'));
    expect(notification, contains('await _ensureMediaSession();'));
  });
}
