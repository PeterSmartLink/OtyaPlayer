import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call/interruption resume reacquires focus for the exact paused player', () {
    final source = File(
      'lib/core/services/audio_session_service.dart',
    ).readAsStringSync();

    expect(source, contains('Player? _playerPausedForInterruption;'));
    expect(
      source,
      contains('_playerPausedForInterruption =\n              _resumeAfterInterruption ? player : null;'),
    );
    expect(source, contains('final interruptedPlayer = _playerPausedForInterruption;'));
    expect(
      source,
      contains('unawaited(_resumeAfterFocusInterruption(interruptedPlayer));'),
    );
    expect(source, contains('Future<void> _resumeAfterFocusInterruption(Player player)'));
    expect(source, contains('final focusGranted = await activate();'));
    expect(source, contains('if (!focusGranted)'));
    expect(
      source,
      contains('identical(PlaybackCoordinator.instance.activePlayer, player)'),
    );
    expect(source, contains('await player.play();'));
  });

  test('duck volume restoration belongs to the player that was actually ducked', () {
    final source = File(
      'lib/core/services/audio_session_service.dart',
    ).readAsStringSync();

    expect(source, contains('Player? _duckedPlayer;'));
    expect(source, contains('_duckedPlayer = player;'));
    expect(source, contains('final duckedPlayer = _duckedPlayer;'));
    expect(
      source,
      contains('identical(PlaybackCoordinator.instance.activePlayer, duckedPlayer)'),
    );
    expect(source, contains('duckedPlayer.setVolume(previous)'));
  });

  test('noisy output still pauses and cancels pending automatic resume', () {
    final source = File(
      'lib/core/services/audio_session_service.dart',
    ).readAsStringSync();
    final noisyStart = source.indexOf('Future<void> _pauseForNoisyOutput()');
    expect(noisyStart, greaterThanOrEqualTo(0));
    final noisy = source.substring(noisyStart);
    expect(noisy, contains('_resumeAfterInterruption = false;'));
    expect(noisy, contains('_playerPausedForInterruption = null;'));
    expect(noisy, contains('await player.pause();'));
  });
}
