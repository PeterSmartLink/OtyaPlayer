import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/application/together_session_controller.dart';
import 'package:otya_player/features/together/domain/together_message.dart';
import 'package:otya_player/features/together/domain/together_session.dart';

TogetherSession _session(DateTime now) {
  return TogetherSession(
    id: 'room-1',
    hostParticipantId: 'host',
    activeMediaFingerprint: 'media-a',
    phase: TogetherSessionPhase.connecting,
    participants: [
      TogetherParticipant(
        id: 'host',
        displayName: 'Peter',
        username: '@peter',
        role: TogetherParticipantRole.host,
        isConnected: true,
        joinedAt: now,
      ),
    ],
    createdAt: now,
  );
}

void main() {
  test('room keeps conversation when host starts next media', () {
    final now = DateTime.utc(2026, 9, 5, 12);
    final controller = TogetherSessionController()..start(_session(now));

    controller.connected(TogetherConnectionPath.nearby, now);
    controller.receiveMessage(
      TogetherMessage(
        id: 'm1',
        sessionId: 'room-1',
        senderParticipantId: 'host',
        text: 'That ending!',
        kind: TogetherMessageKind.text,
        createdAt: now,
      ),
      conversationVisible: true,
    );
    controller.playbackEnded(now.add(const Duration(hours: 2)));
    controller.startNextMedia(
      'media-b',
      now.add(const Duration(hours: 2, minutes: 1)),
    );

    expect(controller.state.session!.activeMediaFingerprint, 'media-b');
    expect(controller.state.session!.mediaRevision, 1);
    expect(controller.state.session!.phase, TogetherSessionPhase.watching);
    expect(controller.state.messages.single.text, 'That ending!');
  });

  test('after-watch room expires after inactivity', () {
    final now = DateTime.utc(2026, 9, 5, 12);
    final controller = TogetherSessionController()..start(_session(now));

    controller.connected(TogetherConnectionPath.directInternet, now);
    controller.playbackEnded(now);

    expect(
      controller.closeIfAfterWatchExpired(
        now.add(const Duration(minutes: 9, seconds: 59)),
      ),
      isFalse,
    );
    expect(
      controller.closeIfAfterWatchExpired(
        now.add(const Duration(minutes: 10)),
      ),
      isTrue,
    );
    expect(controller.state.session!.phase, TogetherSessionPhase.closed);
    expect(controller.state.messages, isEmpty);
  });

  test('v1 refuses a third participant', () {
    final now = DateTime.utc(2026, 9, 5, 12);
    final controller = TogetherSessionController()..start(_session(now));

    controller.addParticipant(
      TogetherParticipant(
        id: 'guest',
        displayName: 'Sarah',
        username: '@sarah',
        role: TogetherParticipantRole.guest,
        isConnected: true,
        joinedAt: now,
      ),
      now,
    );

    expect(
      () => controller.addParticipant(
        TogetherParticipant(
          id: 'guest-2',
          displayName: 'John',
          role: TogetherParticipantRole.guest,
          isConnected: true,
          joinedAt: now,
        ),
        now,
      ),
      throwsStateError,
    );
  });

  test('duplicate messages are ignored and unread state is bounded by visibility', () {
    final now = DateTime.utc(2026, 9, 5, 12);
    final controller = TogetherSessionController()..start(_session(now));
    final message = TogetherMessage(
      id: 'm1',
      sessionId: 'room-1',
      senderParticipantId: 'host',
      text: 'Look here',
      kind: TogetherMessageKind.moment,
      mediaPosition: const Duration(minutes: 18, seconds: 42),
      createdAt: now,
    );

    controller.receiveMessage(message, conversationVisible: false);
    controller.receiveMessage(message, conversationVisible: false);

    expect(controller.state.messages, hasLength(1));
    expect(controller.state.unreadMessages, 1);

    controller.markConversationRead();
    expect(controller.state.unreadMessages, 0);
  });
}
