import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mini player relies on shell safe area and stays close to navigation', () {
    final source = File(
      'lib/features/player/presentation/mini_player.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('MediaQuery.of(context).padding.bottom')));
    expect(source, isNot(contains('8 + bottomInset')));
    expect(source, contains('EdgeInsets.fromLTRB(10, 0, 10, 3)'));
    expect(source, contains('height: 64'));
  });

  test('full Now Playing does not reserve the phone bottom inset twice', () {
    final source = File(
      'lib/features/player/presentation/widgets/audio_player_now_playing_view.dart',
    ).readAsStringSync();

    expect(source, contains('body: SafeArea('));
    expect(
      source,
      isNot(contains('MediaQuery.of(context).padding.bottom + 8')),
    );
    expect(source, contains('const SizedBox(height: 8)'));
  });

  test('dark theme is a quiet mature product canvas', () {
    final colors = File('lib/app/theme/app_colors.dart').readAsStringSync();
    final background = File(
      'lib/shared/widgets/otya_mountain_background.dart',
    ).readAsStringSync();
    final theme = File('lib/app/theme/app_theme.dart').readAsStringSync();

    expect(colors, contains('background = Color(0xFF101014)'));
    expect(colors, contains('surface = Color(0xFF18181E)'));
    expect(colors, contains('brandViolet = Color(0xFF8B6CFF)'));
    expect(colors, contains('brandBlue = brandViolet'));
        expect(background, contains('this.darkness = 0.16'));
    expect(background, contains('this.showGlow = false'));
    expect(background, isNot(contains('_OtyaLightFlowPainter')));
    expect(theme, contains('final background = isDark ? AppColors.background'));
    expect(theme, isNot(contains('Color(0xFF070A10)')));
  });
}
