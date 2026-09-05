import '../domain/together_message.dart';
import '../domain/together_session.dart';
import 'together_policy.dart';

/// In-memory source of truth for one active Together room.
///
/// Networking and Flutter UI deliberately sit outside this controller. This
/// keeps room semantics testable and ensures Together can fail independently
/// without becoming a dependency of local playback.
class TogetherSessionState {
  final TogetherSession? session;
  final List<TogetherMessage> messages;
  final int unreadMessages;
  final DateTime? lastActivityAt;

  const TogetherSessionState({
    this.session,
    this.messages = const [],
    this.unreadMessages = 0,
    this.lastActivityAt,
  });

  bool get hasActiveSession => session?.isActive == true;

  TogetherSessionState copyWith({
    TogetherSession? session,
    bool clearSession = false,
    List<TogetherMessage>? messages,
    int? unreadMessages,
    DateTime? lastActivityAt,
    bool clearLastActivity = false,
  }) {
    return TogetherSessionState(
      session: clearSession ? null : (session ?? this.session),
      messages: messages ?? this.messages,
      unreadMessages: unreadMessages ?? this.unreadMessages,
      lastActivityAt:
          clearLastActivity ? null : (lastActivityAt ?? this.lastActivityAt),
    );
  }
}

class TogetherSessionController {
  TogetherSessionState _state = const TogetherSessionState();

  TogetherSessionState get state => _state;

  void start(TogetherSession session) {
    if (session.participants.isEmpty) {
      throw StateError('A Together room needs at least the host.');
    }
    if (session.participants.length > TogetherPolicy.maxParticipantsV1) {
      throw StateError('Together v1 supports one host and one guest.');
    }
    if (!session.participants.any(
      (participant) => participant.id == session.hostParticipantId,
    )) {
      throw StateError('The host must be part of the Together room.');
    }

    _state = TogetherSessionState(
      session: session,
      messages: const [],
      unreadMessages: 0,
      lastActivityAt: session.createdAt,
    );
  }

  void connected(TogetherConnectionPath path, DateTime now) {
    final session = _requireSession();
    _state = _state.copyWith(
      session: session.copyWith(
        phase: TogetherSessionPhase.watching,
        connectionPath: path,
        clearMediaEndedAt: true,
      ),
      lastActivityAt: now,
    );
  }

  void reconnecting(DateTime now) {
    final session = _requireSession();
    if (!session.isActive) return;
    _state = _state.copyWith(
      session: session.copyWith(phase: TogetherSessionPhase.reconnecting),
      lastActivityAt: now,
    );
  }

  void playbackEnded(DateTime now) {
    final session = _requireSession();
    if (!session.isActive) return;
    _state = _state.copyWith(
      session: session.copyWith(
        phase: TogetherSessionPhase.afterWatch,
        mediaEndedAt: now,
      ),
      lastActivityAt: now,
    );
  }

  /// Keeps the room/conversation alive while replacing only the active media.
  void startNextMedia(String fingerprint, DateTime now) {
    final clean = fingerprint.trim();
    if (clean.isEmpty) throw ArgumentError.value(fingerprint, 'fingerprint');

    final session = _requireSession();
    if (!session.isActive) {
      throw StateError('A closed Together room cannot start another video.');
    }

    _state = _state.copyWith(
      session: session.copyWith(
        activeMediaFingerprint: clean,
        mediaRevision: session.mediaRevision + 1,
        phase: TogetherSessionPhase.watching,
        clearMediaEndedAt: true,
      ),
      lastActivityAt: now,
    );
  }

  void addParticipant(TogetherParticipant participant, DateTime now) {
    final session = _requireSession();
    if (!session.isActive) throw StateError('Together room is closed.');

    final existingIndex = session.participants.indexWhere(
      (item) => item.id == participant.id,
    );
    final updated = [...session.participants];
    if (existingIndex >= 0) {
      updated[existingIndex] = participant;
    } else {
      if (updated.length >= TogetherPolicy.maxParticipantsV1) {
        throw StateError('Together v1 room is full.');
      }
      updated.add(participant);
    }

    _state = _state.copyWith(
      session: session.copyWith(participants: List.unmodifiable(updated)),
      lastActivityAt: now,
    );
  }

  void removeParticipant(String participantId, DateTime now) {
    final session = _requireSession();
    if (participantId == session.hostParticipantId) {
      close(now);
      return;
    }
    final updated = session.participants
        .where((participant) => participant.id != participantId)
        .toList(growable: false);
    _state = _state.copyWith(
      session: session.copyWith(participants: updated),
      lastActivityAt: now,
    );
  }

  void receiveMessage(
    TogetherMessage message, {
    required bool conversationVisible,
  }) {
    final session = _requireSession();
    if (!session.isActive || message.sessionId != session.id) return;
    if (message.text.trim().isEmpty) return;

    final exists = _state.messages.any((item) => item.id == message.id);
    if (exists) return;

    final updated = List<TogetherMessage>.unmodifiable([
      ..._state.messages,
      message,
    ]);
    _state = _state.copyWith(
      messages: updated,
      unreadMessages:
          conversationVisible ? 0 : _state.unreadMessages + 1,
      lastActivityAt: message.createdAt,
    );
  }

  void markConversationRead() {
    if (_state.unreadMessages == 0) return;
    _state = _state.copyWith(unreadMessages: 0);
  }

  /// Closes an inactive After Watch room without requiring a backend timer.
  /// A transport/backend may call the same rule when remote cleanup is needed.
  bool closeIfAfterWatchExpired(DateTime now) {
    final session = _state.session;
    if (session == null || !session.isAfterWatch) return false;

    final last = _state.lastActivityAt ?? session.mediaEndedAt;
    if (last == null) return false;
    if (now.difference(last) < TogetherPolicy.afterWatchIdleTimeout) {
      return false;
    }

    close(now);
    return true;
  }

  void close(DateTime now) {
    final session = _state.session;
    if (session == null) return;
    _state = _state.copyWith(
      session: session.copyWith(phase: TogetherSessionPhase.closed),
      // Conversation is ephemeral in v1 and is removed with the room.
      messages: const [],
      unreadMessages: 0,
      lastActivityAt: now,
    );
  }

  void clearClosedRoom() {
    if (_state.session?.phase != TogetherSessionPhase.closed) return;
    _state = const TogetherSessionState();
  }

  TogetherSession _requireSession() {
    final session = _state.session;
    if (session == null) throw StateError('No active Together room.');
    return session;
  }
}
