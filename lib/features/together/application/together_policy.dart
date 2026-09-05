import '../domain/together_session.dart';

/// Product-level guardrails for OTYA Together.
///
/// These rules keep Together feeling like part of the media player instead of
/// turning OTYA into a second messaging/social app.
abstract final class TogetherPolicy {
  /// V1 is deliberately private and one-to-one for reliability.
  static const int maxParticipantsV1 = 2;

  /// Conversation remains available briefly after playback ends so people can
  /// react, replay, or choose the next item without creating a new room.
  static const Duration afterWatchIdleTimeout = Duration(minutes: 10);

  /// The base app must remain useful without account or internet access.
  static const bool localPlaybackRequiresAccount = false;
  static const bool nearbyTransferRequiresAccount = false;

  /// Remote Together requires authenticated identity; nearby Together may use
  /// a cached account identity or a temporary local display name.
  static const bool remoteTogetherRequiresAccount = true;

  /// Together UI must overlay the existing player and never permanently shrink
  /// the video viewport in portrait, landscape, mini-player, or PiP modes.
  static const bool preserveVideoViewport = true;

  /// Together chat is scoped to the active session; OTYA does not become a
  /// general-purpose messaging app in the first release of this feature.
  static const bool persistentGeneralMessagingV1 = false;

  static bool shouldKeepConversationVisible(TogetherSessionPhase phase) {
    return phase == TogetherSessionPhase.watching ||
        phase == TogetherSessionPhase.afterWatch ||
        phase == TogetherSessionPhase.reconnecting;
  }
}
