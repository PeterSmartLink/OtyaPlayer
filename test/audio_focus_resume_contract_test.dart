import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call/interruption resume reacquires Android audio focus first', () {
    final source = File(
      'lib/core/services/audio_session_service.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> _resumeAfterFocusInterruption(Player player)'));
    expect(source, contains('final focusGranted = await activate();'));
    expect(source, contains('if (!focusGranted)'));
    expect(
      source,
      contains('identical(PlaybackCoordinator.instance.activePlayer, player)'),
    );
    expect(source, contains('await player.play();'));

    final pauseEnd = source.indexOf('case AudioInterruptionType.pause:',
        source.indexOf('switch (event.type)', source.indexOf('return;')));
    expect(pauseEnd, greaterThanOrEqualTo(0));
    final resumeCall = source.indexOf(
      'unawaited(_resumeAfterFocusInterruption(player));',
      pauseEnd,
    );
    expect(resumeCall, greaterThan(pauseEnd));
  });

  test('noisy output still pauses and never auto-resumes', () {
    final source = File(
      'lib/core/services/audio_session_service.dart',
    ).readAsStringSync();
    final noisyStart = source.indexOf('Future<void> _pauseForNoisyOutput()');
    expect(noisyStart, greaterThanOrEqualTo(0));
    final noisy = source.substring(noisyStart);
    expect(noisy, contains('_resumeAfterInterruption = false;'));
    expect(noisy, contains('await player.pause();'));
  });
}
