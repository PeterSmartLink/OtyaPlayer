import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File(
    'lib/features/player/presentation/audio_player_screen.dart',
  ).readAsStringSync();
  final view = File(
    'lib/features/player/presentation/widgets/audio_player_now_playing_view.dart',
  ).readAsStringSync();

  test('audio notifier remains the playback and notification owner', () {
    expect(screen, contains('final Player _player = Player('));
    expect(screen, contains('AudioHandlerSingleton.instance.attachPlayer(_player)'));
    expect(screen, contains('MediaNotificationService.instance.show('));
    expect(
      screen,
      contains("PlaybackCoordinator.instance.register(_player, 'audio')"),
    );

    expect(view, isNot(contains('Player(')));
    expect(view, isNot(contains('AudioHandlerSingleton')));
    expect(view, isNot(contains('MediaNotificationService')));
    expect(view, isNot(contains('PlaybackCoordinator')));
    expect(view, isNot(contains('StreamSubscription')));
  });

  test('idle audio provider cannot steal the system MediaSession', () {
    final initStart = screen.indexOf('  void init() {');
    final initEnd = screen.indexOf('  void _attachStreams()', initStart);
    expect(initStart, greaterThanOrEqualTo(0));
    expect(initEnd, greaterThan(initStart));
    final initBlock = screen.substring(initStart, initEnd);
    expect(
      initBlock,
      isNot(contains('AudioHandlerSingleton.instance.attachPlayer(_player)')),
    );

    final loadStart = screen.indexOf('  Future<bool> _loadCurrent(');
    final loadEnd = screen.indexOf('  Future<void> load(', loadStart);
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadEnd, greaterThan(loadStart));
    final loadBlock = screen.substring(loadStart, loadEnd);
    expect(
      loadBlock,
      contains("PlaybackCoordinator.instance.register(_player, 'audio')"),
    );
    expect(
      loadBlock,
      contains('AudioHandlerSingleton.instance.attachPlayer(_player)'),
    );
  });

  test('notification metadata follows successful audio ownership', () {
    final loadStart = screen.indexOf('  Future<void> load(');
    final notification = screen.indexOf('      _updateNotification();', loadStart);
    final loadedCheck = screen.indexOf('      if (!loaded ||', loadStart);
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadedCheck, greaterThan(loadStart));
    expect(notification, greaterThan(loadedCheck));
  });

  test('now playing layout is presentation-only and delegated by the screen', () {
    expect(
      screen,
      contains("part 'widgets/audio_player_now_playing_view.dart';"),
    );
    expect(screen, contains('return _AudioPlayerNowPlayingView('));
    expect(view, contains('class _AudioPlayerNowPlayingView'));
    expect(view, contains('WallpaperScaffold('));
    expect(view, contains('_AlbumArt('));
    expect(view, contains('_SeekBar('));
  });
}
