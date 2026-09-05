import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File(
    'lib/features/player/presentation/video_player_screen.dart',
  ).readAsStringSync();
  final overlays = File(
    'lib/features/player/presentation/widgets/video_player_overlays.dart',
  ).readAsStringSync();

  test('video screen remains the single playback lifecycle owner', () {
    expect(screen, contains('Player? _player;'));
    expect(screen, contains('void _attachPlayer(Player player)'));
    expect(screen, contains('MediaKitEngine('));

    // The lifecycle owner snapshots the current player before teardown so
    // Together can detach from that exact instance before the playback
    // coordinator releases it. Keep the ownership contract semantic rather
    // than coupling this test to the old `_player!` spelling.
    expect(screen, contains('final player = _player;'));
    expect(screen, contains('PlaybackCoordinator.instance.unregister(player)'));
    expect(
      screen,
      contains('NearbyTogetherRuntime.instance.detachPlayer(player)'),
    );

    expect(overlays, isNot(contains('MediaKitEngine(')));
    expect(overlays, isNot(contains('PlaybackCoordinator')));
    expect(overlays, isNot(contains('Player? _player')));
    expect(overlays, isNot(contains('StreamSubscription')));
  });

  test('video presentation helpers live outside the lifecycle owner', () {
    expect(screen, contains("import 'widgets/video_player_overlays.dart';"));
    expect(screen, contains('VideoPlayerControlsOverlay('));
    expect(screen, contains('VideoPlayerLockOverlay('));
    expect(screen, contains('VideoAudioTrackSheet('));
    expect(screen, contains('VideoInfoRow('));

    expect(overlays, contains('class VideoPlayerControlsOverlay'));
    expect(overlays, contains('class VideoPlayerLockOverlay'));
    expect(overlays, contains('class VideoAudioTrackSheet'));
    expect(overlays, contains('class VideoInfoRow'));
  });
}
