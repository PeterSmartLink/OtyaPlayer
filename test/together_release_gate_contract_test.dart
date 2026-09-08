import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gate = File(
    'lib/features/together/application/together_release_gate.dart',
  ).readAsStringSync();
  final player = File(
    'lib/features/player/presentation/video_player_screen.dart',
  ).readAsStringSync();

  test('Watch Together remains disabled by default in public builds', () {
    expect(gate, contains("'OTYA_ENABLE_WATCH_TOGETHER'"));
    expect(gate, contains('defaultValue: false'));
  });

  test('video player gates both discovery and entry', () {
    expect(
      player,
      contains('if (TogetherReleaseGate.isPubliclyEnabled)'),
    );
    expect(
      player,
      contains('if (!TogetherReleaseGate.isPubliclyEnabled)'),
    );
    expect(
      player,
      contains('Watch Together is still being tested'),
    );
  });

  test('Together implementation remains available for internal validation', () {
    expect(player, contains('showTogetherEntrySheet(context)'));
    expect(player, contains('showNearbyTogetherHostSheet'));
    expect(player, contains('showAnywhereTogetherHostSheet'));
  });
}
