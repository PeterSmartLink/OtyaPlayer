import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online services stay outside the pre-first-frame startup path', () {
    final source = File('lib/app/app.dart').readAsStringSync();

    final initStart = source.indexOf('void initState()');
    final firstFrame = source.indexOf(
      'SchedulerBinding.instance.addPostFrameCallback',
      initStart,
    );

    expect(initStart, greaterThanOrEqualTo(0));
    expect(firstFrame, greaterThan(initStart));

    final beforeFirstFrame = source.substring(initStart, firstFrame);

    expect(beforeFirstFrame, isNot(contains('RemoteControlService.instance.init')));
    expect(beforeFirstFrame, isNot(contains('refreshSeasonalTheme')));
    expect(beforeFirstFrame, isNot(contains('FcmService.instance.init')));
    expect(beforeFirstFrame, isNot(contains('UpdateService.instance')));
    expect(beforeFirstFrame, isNot(contains('AuthService.instance')));
    expect(beforeFirstFrame, isNot(contains('http.')));
    expect(beforeFirstFrame, isNot(contains('OnlineMusicService')));
    expect(beforeFirstFrame, isNot(contains('JAMENDO')));
  });

  test('startup hydrates App Lock before revealing router content', () {
    final source = File('lib/app/app.dart').readAsStringSync();
    final hydrate = source.indexOf(
      'ref.read(settingsProvider.notifier).hydrate(savedSettings)',
    );
    final reveal = source.indexOf('_checking = false', hydrate);

    expect(hydrate, greaterThanOrEqualTo(0));
    expect(reveal, greaterThan(hydrate));
    expect(source, contains('_hydrateStartupPrivacyAndOnboarding()'));
  });

  test('media-session playback does not request ordinary notification consent', () {
    final source = File(
      'lib/core/services/media_notification_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('NotificationService.instance.requestPermission')));
    expect(source, isNot(contains('existsSync()')));
  });

  test('Otya startup keeps local playback independent of Firebase config', () {
    final source = File('lib/core/services/fcm_service.dart').readAsStringSync();

    expect(source, contains('if (!OtyaFirebaseConfig.configured)'));
    expect(
      source,
      contains('Disabled: Firebase build configuration is incomplete'),
    );
    expect(source, contains('non-fatal'));
  });

  test('global search is local-first and has no music-provider request path', () {
    final source =
        File('lib/features/search/smart_search_sheet.dart').readAsStringSync();

    expect(source, contains('_mediaMatches(library)'));
    expect(source, contains('_groupMatches(library)'));
    expect(source, contains('_playlistMatches(playlists)'));
    expect(source, isNot(contains('OnlineMusicService')));
    expect(source, isNot(contains('OnlineTrack')));
    expect(source, isNot(contains('Connectivity().checkConnectivity()')));
    expect(source, isNot(contains('cached_network_image')));
    expect(
      source,
      contains('Search does not contact a music provider while you type.'),
    );
  });

  test('Online Music implementation and provider config stay removed', () {
    expect(
      File('lib/features/music/online/online_music_screen.dart').existsSync(),
      isFalse,
    );
    expect(
      File('lib/features/music/online/online_music_service.dart').existsSync(),
      isFalse,
    );
    expect(
      File('lib/features/music/online/spotify_service.dart').existsSync(),
      isFalse,
    );

    final environment = File('lib/core/config/environment.dart').readAsStringSync();
    final music = File(
      'lib/features/music/presentation/music_tab_screen.dart',
    ).readAsStringSync();

    expect(environment, isNot(contains('onlineMusicUrl')));
    expect(environment, isNot(contains('JAMENDO')));
    expect(environment, isNot(contains('SPOTIFY_CLIENT_ID')));
    expect(music, isNot(contains('OnlineMusicScreen')));
    expect(music, isNot(contains('Online Music')));
  });

  test('Transfer receiver is restricted to authenticated local media', () {
    final receiver = File(
      'lib/features/transfer/data/media_receiver.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/features/transfer/data/transfer_security_policy.dart',
    ).readAsStringSync();
    final sender = File(
      'lib/features/transfer/data/media_sender.dart',
    ).readAsStringSync();

    expect(receiver, contains('isAllowedTransferUri(uri)'));
    expect(receiver, contains('request.followRedirects = false'));
    expect(receiver, contains("response.headers.value('X-Otya-Transfer')"));
    expect(receiver, contains("contentType.startsWith('audio/')"));
    expect(receiver, contains("contentType.startsWith('video/')"));
    expect(receiver, contains('_maxTransferBytes'));
    expect(policy, contains("RegExp(r'^[a-f0-9]{64}\$')"));
    expect(policy, contains('a == 10'));
    expect(policy, contains('a == 192 && b == 168'));
    expect(sender, contains("headers.set('X-Otya-Transfer', '1')"));
    expect(sender, contains("'X-Content-Type-Options', 'nosniff'"));
    expect(sender, contains('_supportedMediaExtensions'));
    expect(sender, contains('HttpHeaders.rangeHeader'));
    expect(sender, contains('_tokenMatches(requestToken, _token)'));
  });
}
