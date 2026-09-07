import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/application/anywhere_together_runtime.dart';

void main() {
  test('Anywhere runtime stays a Together layer over the existing player', () {
    expect(
      AnywhereTogetherRuntime.supportedReactions,
      containsAll(<String>{'❤️', '😂', '😮', '👏'}),
    );
    expect(
      AnywherePlaybackSourceKind.values,
      containsAll(<AnywherePlaybackSourceKind>{
        AnywherePlaybackSourceKind.localCopy,
        AnywherePlaybackSourceKind.hostPeerStream,
      }),
    );

    final source = File(
      'lib/features/together/application/anywhere_together_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('TogetherSessionController'));
    expect(source, contains('MediaKitTogetherAdapter'));
    expect(source, contains('AnywhereTogetherMediaHost'));
    expect(source, contains('AnywhereTogetherMediaGuest'));
    expect(source, contains('TogetherConnectionPath.internet'));
    expect(source, contains("_peer?.send('chat'"));
    expect(source, contains("_peer?.send('moment'"));
    expect(source, contains("_peer?.send('reaction'"));

    // Anywhere must reuse OTYA's existing media_kit Player and encrypted data
    // channels. It must never grow into a camera/microphone capture stack.
    expect(source, isNot(contains('getUserMedia')));
    expect(source, isNot(contains('getDisplayMedia')));
    expect(source, isNot(contains('MediaKitEngine(')));
  });
}
