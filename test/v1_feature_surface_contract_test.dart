// Otya v1 release contract: this file also triggers strict CI after source patches.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Video Music and Me remain the main product navigation', () {
    final router = File('lib/app/router.dart').readAsStringSync();
    expect(router, contains("static const _routes = ['/', '/music', '/myspace']"));
    expect(router, contains("label: 'Video'"));
    expect(router, contains("label: 'Music'"));
    expect(router, contains("label: 'Me'"));
    expect(router, isNot(contains("label: 'Next'")));
    expect(router, isNot(contains("label: 'Together'")));
  });

  test('Me exposes every required Otya v1 hub action without consumer AI', () {
    final source = File(
      'lib/features/my_space/presentation/my_space_hub_screen.dart',
    ).readAsStringSync();

    for (final label in [
      'Send',
      'Files',
      'Private',
      'Convert video to audio',
      'Playlists',
      'History',
      'Tools',
      'Appearance',
      'Storage',
    ]) {
      expect(source, contains("'$label'"), reason: '$label must stay reachable');
    }

    for (final route in [
      '/transfer',
      '/tools/folders',
      '/vault',
      '/playlists',
      '/history',
      '/theme',
      '/settings/storage',
    ]) {
      expect(source, contains("'$route'"), reason: '$route must stay wired');
    }

    expect(source, isNot(contains('_NextCard(onTap:')));
    expect(source, isNot(contains("context.push('/support')")));
    expect(source, isNot(contains("Text('Next'")));
    expect(source, contains("title: 'Trim video'"), reason: 'Trim must stay reachable');
    expect(source, contains("title: 'Equalizer'"), reason: 'Equalizer must stay reachable');
  });

  test('App Lock is persisted, user-accessible and mounted at app root', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    final settings = File(
      'lib/features/settings/settings_provider.dart',
    ).readAsStringSync();
    final settingsUi = File(
      'lib/features/settings/presentation/settings_detail_screen.dart',
    ).readAsStringSync();
    final gate = File(
      'lib/features/settings/app_lock_screen.dart',
    ).readAsStringSync();

    expect(app, contains('AppLockGate('));
    expect(settings, contains('setAppLock'));
    expect(settings, contains("_kAppLock = 'settings_app_lock'"));
    expect(settings, contains('appLockEnabled: p.getBool(_kAppLock) ?? false'));
    expect(settingsUi, contains("title: 'App Lock'"));
    expect(gate, contains('settingsProvider.select'));
    expect(gate, contains('AppLifecycleState.paused'));
  });

  test('Private keeps authentication, persistent throttle and safe restore', () {
    final screen = File(
      'lib/features/vault/presentation/vault_lock_screen.dart',
    ).readAsStringSync();
    final service =
        File('lib/core/services/vault_service.dart').readAsStringSync();

    expect(screen, contains('LocalAuthentication'));
    expect(screen, contains('vault_pin_failed_attempts'));
    expect(screen, contains('vault_pin_blocked_until_ms'));
    expect(screen, contains('_pinMaxAttempts = 5'));
    expect(service, contains('_availableRestorePath'));
    expect(service, contains(r'(restored $index)'));
    expect(service, contains('Refusing path outside Private storage'));
  });

  test('Send keeps authenticated local-only streaming and safe resume', () {
    final receiver = File(
      'lib/features/transfer/data/media_receiver.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/features/transfer/data/transfer_security_policy.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();

    expect(receiver, contains('isAllowedTransferUri(uri)'));
    expect(policy, contains("uri.path != '/media'"));
    expect(policy, contains("RegExp(r'^[a-f0-9]{64}\$')"));
    expect(receiver, contains('FileMode.append'));
    expect(receiver, contains('.otya-transfer'));
    expect(receiver, contains('TransferCancelledException'));
    expect(screen, contains("split('/').last"));
  });

  test('Music keeps queue, favorites, repeat, lyrics, EQ, sleep and Drive Mode', () {
    final screen = File(
      'lib/features/player/presentation/audio_player_screen.dart',
    ).readAsStringSync();
    final widgets = File(
      'lib/features/player/presentation/widgets/audio_player_widgets.dart',
    ).readAsStringSync();
    final nowPlaying = File(
      'lib/features/player/presentation/widgets/audio_player_now_playing_view.dart',
    ).readAsStringSync();
    final player = '$screen\n$widgets\n$nowPlaying';

    for (final marker in [
      'toggleFavorite()',
      'toggleShuffle()',
      'cycleRepeat()',
      'SleepTimerButton(',
      'LyricsSheet(',
      "context.push('/player/equalizer')",
      'CarModeScreen()',
      'skipNext()',
      'skipPrevious()',
    ]) {
      expect(player, contains(marker), reason: '$marker must stay wired');
    }
  });

  test('Video keeps gestures, PiP, tracks and local processing tools', () {
    final player = File(
      'lib/features/player/presentation/video_player_screen.dart',
    ).readAsStringSync();
    final gestures = File(
      'lib/features/player/presentation/widgets/video_gesture_layer.dart',
    ).readAsStringSync();

    expect(player, contains('setSubtitleTrack'));
    expect(player, contains('setAudioTrack'));
    expect(player, contains('PipService.instance.enterPip'));
    expect(player, contains('extractAudio'));
    expect(player, contains("context.push('/tools/whatsapp'"));
    expect(gestures, contains('_applyBrightness'));
    expect(gestures, contains('_applyVolume'));
    expect(gestures, contains('onDoubleTapDown'));
    expect(gestures, contains('beginSpeedBoost(rate: 2.0)'));
  });

  test('Downloads remain a view of normal Video and Music media', () {
    final downloads = File(
      'lib/features/downloads/presentation/downloads_screen.dart',
    ).readAsStringSync();
    expect(downloads, contains("path.contains('/download/')"));
    expect(downloads, contains("path.contains('/downloads/')"));
    expect(downloads, contains("context.push('/player/video'"));
    expect(downloads, contains("context.push('/player/audio'"));
  });

  test('consumer AI remains removed from public app routing', () {
    final router = File('lib/app/router.dart').readAsStringSync();
    final me = File(
      'lib/features/my_space/presentation/my_space_hub_screen.dart',
    ).readAsStringSync();
    final about = File(
      'lib/features/settings/presentation/about_screen.dart',
    ).readAsStringSync();

    expect(router, isNot(contains('features/ai/otya_support_screen.dart')));
    expect(router, contains("GoRoute(path: '/support', redirect: (_, __) => '/about')"));
    expect(router, contains("GoRoute(path: '/ai', redirect: (_, __) => '/about')"));
    expect(me, isNot(contains("context.push('/support')")));
    expect(about, isNot(contains("context.push('/support')")));
    expect(about, isNot(contains("label: 'Next'")));
  });

  test('Account keeps Google, password, consent, recovery and 2FA flows', () {
    final auth = File(
      'lib/features/auth/account_access_screen.dart',
    ).readAsStringSync();
    expect(auth, contains('Continue with Google'));
    expect(auth, contains('Forgot password?'));
    expect(auth, contains('Terms of Service'));
    expect(auth, contains('Privacy Policy'));
    expect(auth, contains('Authenticator code'));
    expect(auth, contains('Recovery code'));
    expect(auth, contains('FcmService.instance.syncRegistration'));
  });

  test('Notifications keep contextual permission and safe FCM routing', () {
    final local =
        File('lib/core/services/notification_service.dart').readAsStringSync();
    final fcm = File('lib/core/services/fcm_service.dart').readAsStringSync();
    expect(local, contains('requestNotificationsPermission'));
    expect(fcm, contains('_allowedRoutes'));
    expect(fcm, contains('FirebaseMessaging.onBackgroundMessage'));
    expect(fcm, contains('showUpdateNotification'));
    expect(fcm, contains('protectedHeaders'));
  });
}
