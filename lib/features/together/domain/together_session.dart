/// Core domain model for OTYA Together.
///
/// This file intentionally has no Flutter, network, database, or WebRTC
/// dependency. Together must remain an optional layer above local playback,
/// never a requirement for opening or playing local media.
enum TogetherSessionPhase {
  creating,
  connecting,
  watching,
  afterWatch,
  reconnecting,
  closed,
}

enum TogetherConnectionPath {
  /// Same Wi-Fi, hotspot, or other local peer path. Internet is not required.
  nearby,

  /// Direct peer-to-peer path across the internet.
  directInternet,

  /// Encrypted peer traffic relayed when a direct internet path is unavailable.
  relayedInternet,
}

enum TogetherParticipantRole { host, guest }

class TogetherParticipant {
  final String id;
  final String displayName;
  final String? username;
  final TogetherParticipantRole role;
  final bool isConnected;
  final DateTime joinedAt;

  const TogetherParticipant({
    required this.id,
    required this.displayName,
    required this.role,
    required this.isConnected,
    required this.joinedAt,
    this.username,
  });

  TogetherParticipant copyWith({
    String? displayName,
    String? username,
    bool clearUsername = false,
    TogetherParticipantRole? role,
    bool? isConnected,
  }) {
    return TogetherParticipant(
      id: id,
      displayName: displayName ?? this.displayName,
      username: clearUsername ? null : (username ?? this.username),
      role: role ?? this.role,
      isConnected: isConnected ?? this.isConnected,
      joinedAt: joinedAt,
    );
  }
}

class TogetherSession {
  final String id;
  final String hostParticipantId;

  /// Fingerprint for the media currently attached to the room. This is not a
  /// permanent room identifier: the host can choose another movie while the
  /// same participants and conversation remain connected.
  final String activeMediaFingerprint;

  /// Increments whenever the host replaces the active media. Playback/control
  /// packets can carry this value so stale packets from the previous movie are
  /// ignored without creating a new Together room.
  final int mediaRevision;

  final TogetherSessionPhase phase;
  final TogetherConnectionPath? connectionPath;
  final List<TogetherParticipant> participants;
  final DateTime createdAt;
  final DateTime? mediaEndedAt;

  const TogetherSession({
    required this.id,
    required this.hostParticipantId,
    required this.activeMediaFingerprint,
    required this.phase,
    required this.participants,
    required this.createdAt,
    this.mediaRevision = 0,
    this.connectionPath,
    this.mediaEndedAt,
  });

  bool get isActive => phase != TogetherSessionPhase.closed;

  bool get isWatching => phase == TogetherSessionPhase.watching;

  bool get isAfterWatch => phase == TogetherSessionPhase.afterWatch;

  int get connectedParticipantCount =>
      participants.where((participant) => participant.isConnected).length;

  TogetherSession copyWith({
    String? activeMediaFingerprint,
    int? mediaRevision,
    TogetherSessionPhase? phase,
    TogetherConnectionPath? connectionPath,
    bool clearConnectionPath = false,
    List<TogetherParticipant>? participants,
    DateTime? mediaEndedAt,
    bool clearMediaEndedAt = false,
  }) {
    return TogetherSession(
      id: id,
      hostParticipantId: hostParticipantId,
      activeMediaFingerprint:
          activeMediaFingerprint ?? this.activeMediaFingerprint,
      mediaRevision: mediaRevision ?? this.mediaRevision,
      phase: phase ?? this.phase,
      connectionPath: clearConnectionPath
          ? null
          : (connectionPath ?? this.connectionPath),
      participants: participants ?? this.participants,
      createdAt: createdAt,
      mediaEndedAt:
          clearMediaEndedAt ? null : (mediaEndedAt ?? this.mediaEndedAt),
    );
  }
}
