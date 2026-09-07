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

  test('every publication path shares one Android runtime configuration', () {
    final validation = File('.github/workflows/release-mode-validation.yml')
        .readAsStringSync();
    final direct =
        File('.github/workflows/release-apk.yml').readAsStringSync();
    final play =
        File('.github/workflows/play-closed-test.yml').readAsStringSync();
    final release = File('.github/workflows/release.yml').readAsStringSync();
    final shared = File('scripts/android-release-config.sh').readAsStringSync();

    for (final workflow in [validation, direct, play, release]) {
      expect(
        workflow,
        contains('scripts/android-release-config.sh'),
        reason: 'Release workflows must not maintain private copies of Firebase/Google runtime defines.',
      );
    }

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
}
