import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/data/nearby_together_channel.dart';

void main() {
  test('critical Nearby Together messages require acknowledgement', () {
    for (final type in const {
      'hello',
      'ready',
      'media',
      'chat',
      'moment',
      'reaction',
    }) {
      expect(
        NearbyTogetherProtocol.requiresAck(type),
        isTrue,
        reason: '$type must not be silently lost',
      );
    }
  });

  test('real-time sync samples stay lossy', () {
    for (final type in const {'state', 'ping', 'pong', 'bye', 'ack'}) {
      expect(
        NearbyTogetherProtocol.requiresAck(type),
        isFalse,
        reason: '$type must not build a stale retry queue',
      );
    }
  });

  test('ack frames round-trip through the protocol', () {
    final encoded = NearbyTogetherProtocol.encode(
      'ack',
      const {'message_id': 'message-123'},
    );
    final decoded = NearbyTogetherProtocol.decode(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.type, 'ack');
    expect(decoded.payload['message_id'], 'message-123');
    expect(decoded.id, isNotEmpty);
  });

  test('reliable frames retain stable identity when the same frame is resent', () {
    final encoded = NearbyTogetherProtocol.encode(
      'chat',
      const {'text': 'hello'},
    );
    final first = NearbyTogetherProtocol.decode(encoded);
    final retransmitted = NearbyTogetherProtocol.decode(encoded);

    expect(first, isNotNull);
    expect(retransmitted, isNotNull);
    expect(first!.id, retransmitted!.id);
    expect(first.sentAt, retransmitted.sentAt);
    expect(first.payload, retransmitted.payload);
  });
}
