import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video owns a compact Together live activity layer', () {
    final player = File(
      'lib/features/player/presentation/video_player_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/features/together/presentation/together_ambient_overlay.dart',
    ).readAsStringSync();

    expect(player, contains('together_ambient_overlay.dart'));
    expect(player, contains('TogetherAmbientOverlay('));
    expect(player, contains('controlsVisible: _controlsVisible'));
    expect(player, contains('_showActiveTogetherRoom()'));

    expect(overlay, contains('const Duration(seconds: 8)'));
    expect(overlay, contains('const Duration(seconds: 4)'));
    expect(overlay, contains('visibleMessages.length <= 3'));
    expect(overlay, contains('message.kind != TogetherMessageKind.reaction'));
    expect(overlay, contains('AppColors.background.withValues(alpha: .42)'));
    expect(overlay, contains("return 'You'"));
  });

  test('ambient layer avoids the playback-control region', () {
    final overlay = File(
      'lib/features/together/presentation/together_ambient_overlay.dart',
    ).readAsStringSync();

    expect(overlay, contains('widget.controlsVisible'));
    expect(overlay, contains('154.0'));
    expect(overlay, contains('118.0'));
    expect(overlay, contains('Alignment'));
  });
}
