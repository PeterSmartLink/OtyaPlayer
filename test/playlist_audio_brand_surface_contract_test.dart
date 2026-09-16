import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist detail stays one-column and uses real local media metadata', () {
    final source = File(
      'lib/features/playlists/playlist_screen.dart',
    ).readAsStringSync();

    expect(source, contains('AspectRatio('));
    expect(source, contains('aspectRatio: 16 / 9'));
    expect(source, contains('item.formattedSize'));
    expect(source, contains('item.formattedDuration'));
    expect(source, contains('getSeekPosition(item.id)'));
    expect(source, contains("label: 'NOW PLAYING'"));
    expect(source, contains("context.push('/player/video'"));
    expect(source, contains("context.push('/player/audio'"));
    expect(source, contains('AlbumArtThumb('));

    // Concept-art-only catalog metadata must not leak into the real product.
    expect(source, isNot(contains("'Trending'")));
    expect(source, isNot(contains("'TV Shows'")));
    expect(source, isNot(contains("'4K'")));
  });

  test('audio Now Playing keeps the real Otya control surface', () {
    final source = File(
      'lib/features/player/presentation/widgets/audio_player_now_playing_view.dart',
    ).readAsStringSync();

    for (final marker in [
      'SleepTimerButton(',
      'onFavorite',
      '_SeekBar(',
      'onShuffle',
      'onSpeed',
      '_RepeatBtn(',
      'onPrevious',
      'onSkipBack',
      'onPlayPause',
      'onSkipForward',
      'onNext',
      "label: 'Lyrics'",
      "label: 'Equalizer'",
      "label: 'Up Next'",
      "label: 'Share'",
    ]) {
      expect(source, contains(marker), reason: '$marker must remain wired');
    }

    expect(source, contains('AppColors.accentGradientDiag'));
    expect(source, contains("'Now playing'"));
    expect(source, isNot(contains('AppColors.brandCyan')));
  });

  test('default background stays quiet and leaves visual richness to media', () {
    final background = File(
      'lib/shared/widgets/otya_mountain_background.dart',
    ).readAsStringSync();
    final colors = File('lib/app/theme/app_colors.dart').readAsStringSync();

    expect(background, contains('this.showGlow = false'));
    expect(background, isNot(contains('_OtyaLightFlowPainter')));
    expect(background, contains('const ColoredBox(color: AppColors.background)'));
    expect(colors, contains('brandViolet = Color(0xFF8B6CFF)'));
    expect(colors, contains('brandBlue = brandViolet'));
  });
}