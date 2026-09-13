import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gate = File(
    'lib/features/together/application/together_release_gate.dart',
  ).readAsStringSync();
  final player = File(
    'lib/features/player/presentation/video_player_screen.dart',
  ).readAsStringSync();

  test('Watch Together is enabled by default in public builds', () {
    expect(gate, contains("'OTYA_ENABLE_WATCH_TOGETHER'"));
    expect(gate, contains('defaultValue: true'));
  });

  test('video player keeps the emergency release gate around discovery and entry', () {
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
      contains('Watch Together is disabled in this emergency rollback build.'),
    );
    expect(player, isNot(contains('still being tested')));
  });

  test('Together implementation remains available to public release builds', () {
    expect(player, contains('showTogetherEntrySheet(context)'));
    expect(player, contains('showNearbyTogetherHostSheet'));
    expect(player, contains('showAnywhereTogetherHostSheet'));
  });
}
