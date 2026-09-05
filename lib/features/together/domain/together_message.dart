/// Lightweight conversation model for an active OTYA Together session.
///
/// This is intentionally session-scoped. It is not a general messaging model
/// and does not introduce inboxes, feeds, followers, or permanent chat as a
/// requirement for the media player.
enum TogetherMessageKind {
  text,
  moment,
  reaction,
  system,
}

class TogetherMessage {
  static const int maxTextLength = 500;

  final String id;
  final String sessionId;
  final String? senderParticipantId;
  final String text;
  final TogetherMessageKind kind;
  final DateTime createdAt;

  /// Present only for a media-aware Moment message.
  final Duration? mediaPosition;

  TogetherMessage({
    required this.id,
    required this.sessionId,
    required this.text,
    required this.kind,
    required this.createdAt,
    this.senderParticipantId,
    this.mediaPosition,
  })  : assert(text.length <= maxTextLength),
        assert(
          kind != TogetherMessageKind.moment || mediaPosition != null,
          'Moment messages require a media position.',
        );

  bool get isMoment => kind == TogetherMessageKind.moment;
  bool get isReaction => kind == TogetherMessageKind.reaction;
}
