import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resuming in-app playback restores the system media session', () {
    final source = File(
      'lib/features/player/presentation/audio_player_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('AudioHandlerSingleton.instance.attachPlayer(_player);'),
    );
    expect(source, contains("register(_player, 'audio')"));
    expect(source, contains('AudioSessionService.instance.activate()'));
  });

  test('system playback claims focus and stop releases it', () {
    final source =
        File('lib/core/services/audio_handler.dart').readAsStringSync();

    expect(source, contains('AudioSessionService.instance.activate()'));
    expect(source, contains('AudioSessionService.instance.deactivate()'));
    expect(source, contains('Future<void> onNotificationDeleted()'));
    expect(source, contains('await stop();'));
  });

  test('system media session publishes a terminal state when media ends', () {
    final source =
        File('lib/core/services/audio_handler.dart').readAsStringSync();

    expect(source, contains('player.stream.completed.listen((completed)'));
    expect(source, contains('AudioProcessingState.completed'));
    expect(source, contains('_completedSub?.cancel();'));
    expect(source, contains('playing: false'));
  });

  test('Android exposes a media playback foreground service', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'),
    );
    expect(
      manifest,
      contains('android:foregroundServiceType="mediaPlayback"'),
    );
    expect(
      manifest,
      contains('com.ryanheise.audioservice.MediaButtonReceiver'),
    );
  });

  test('paused audio keeps its foreground media session without art preload', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, contains('androidStopForegroundOnPause: false'));
    expect(main, contains('androidNotificationOngoing: true'));
    expect(main, contains('preloadArtwork: false'));
  });

  test('Now Playing state is published before artwork resolution', () {
    final source = File(
      'lib/core/services/media_notification_service.dart',
    ).readAsStringSync();

    final showStart = source.indexOf('Future<void> show({');
    final immediateState = source.indexOf('_publishNowPlaying(', showStart);
    final artwork = source.indexOf(
      'final artUri = await _stableArtUri(albumArtPath, id);',
      showStart,
    );

    expect(showStart, greaterThanOrEqualTo(0));
    expect(immediateState, greaterThan(showStart));
    expect(artwork, greaterThan(immediateState));
    expect(
      source,
      contains('generation != _metadataGeneration || artUri == null'),
    );
  });

  test('Now Playing metadata is published before the first async wait', () {
    final source = File(
      'lib/core/services/media_notification_service.dart',
    ).readAsStringSync();

    final showStart = source.indexOf('Future<void> show({');
    final showEnd = source.indexOf('Future<void> showWithBitmap({', showStart);
    final show = source.substring(showStart, showEnd);
    final metadata = show.indexOf('_publishNowPlaying(');
    final firstAwait = show.indexOf('await init()');

    expect(showStart, greaterThanOrEqualTo(0));
    expect(showEnd, greaterThan(showStart));
    expect(metadata, greaterThanOrEqualTo(0));
    expect(firstAwait, greaterThan(metadata));
  });

  test('recovery publishes metadata before attaching a live player', () {
    final source =
        File('lib/core/services/audio_handler.dart').readAsStringSync();

    final setterStart = source.indexOf('set handler(OtyaAudioHandler? h)');
    final setterEnd = source.indexOf('void attachPlayer(Player player)', setterStart);
    final setter = source.substring(setterStart, setterEnd);

    final metadata = setter.indexOf('h.mediaItem.add(');
    final attach = setter.indexOf('h.attachPlayer(pendingPlayer);');

    expect(setterStart, greaterThanOrEqualTo(0));
    expect(setterEnd, greaterThan(setterStart));
    expect(metadata, greaterThanOrEqualTo(0));
    expect(attach, greaterThan(metadata));
  });
}
