import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio screen teardown never reads its detached Riverpod ref', () {
    final source = File(
      'lib/features/player/presentation/audio_player_screen.dart',
    ).readAsStringSync();
    final screen = source.split('class _AudioPlayerScreenState').last;
    final dispose = screen
        .split('void dispose() {').last
        .split('void _showQueue()').first;

    expect(dispose, isNot(contains('ref.read')));
    expect(dispose, isNot(contains('_activeItem')));
    expect(
      dispose.indexOf('removeObserver(this)'),
      lessThan(dispose.indexOf('saveCurrentPosition()')),
    );
    expect(
      screen,
      contains('addPostFrameCallback((_) {\n      if (!mounted) return;'),
    );
  });

  test('full audio player follows the active queue item after skips', () {
    final screen = File(
      'lib/features/player/presentation/audio_player_screen.dart',
    ).readAsStringSync();
    final nowPlaying = File(
      'lib/features/player/presentation/widgets/audio_player_now_playing_view.dart',
    ).readAsStringSync();
    final player = '$screen\n$nowPlaying';

    expect(
      screen,
      contains(
        'final activeItem = ref.watch(miniPlayerItemProvider) ?? widget.mediaItem;',
      ),
    );
    expect(player, contains('albumArtPath: activeItem.albumArtPath'));
    expect(player, contains('activeItem.title'));
    expect(player, contains("activeItem.artist ?? 'Unknown Artist'"));
    expect(player, contains('[XFile(activeItem.filePath)]'));
    expect(screen, contains('_startLoad(activeItem);'));
    expect(screen, contains('_playerNotifier.saveCurrentPosition()'));
    expect(screen, contains('final id = _currentItemId;'));
  });

  test('album art resolution ignores stale async completions', () {
    final player = File(
      'lib/features/player/presentation/widgets/audio_player_widgets.dart',
    ).readAsStringSync();

    expect(player, contains('int _resolveGeneration = 0;'));
    expect(player, contains('final generation = ++_resolveGeneration;'));
    expect(player, contains('generation != _resolveGeneration'));
  });
}
