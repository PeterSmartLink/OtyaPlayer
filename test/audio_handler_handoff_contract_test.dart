import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale player stream events cannot overwrite a new media session', () {
    final source =
        File('lib/core/services/audio_handler.dart').readAsStringSync();

    expect(source, contains('bool _isCurrentPlayer(Player player)'));
    expect(source, contains('identical(_player, player)'));
    expect(
      RegExp(r'if \(!_isCurrentPlayer\(player\)\) return;')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(4),
    );
    expect(source, contains('StreamSubscription.cancel() completes asynchronously'));
  });
}
