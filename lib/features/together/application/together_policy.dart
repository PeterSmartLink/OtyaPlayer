import '../domain/together_session.dart';

/// Product-level guardrails for OTYA Together.
///
/// These rules keep Together feeling like part of the media player instead of
/// turning OTYA into a second messaging/social app. Research ideas may be
/// represented here before they are enabled, but they must not become public
/// behavior until the earlier reliability and data-usage gates have passed.
abstract final class TogetherPolicy {
  /// Design ceiling for the first small-group experience once groups are
  /// actually released: one host plus up to three friends.
  ///
  /// This is not permission to ship group networking yet. Core two-device
  /// Together must pass first.
  static const int maxParticipantsV1 = 4;
  static const int maxInvitedFriendsV1 = maxParticipantsV1 - 1;

  /// Release order: prove the simple two-device path before enabling group
  /// networking or more expensive distribution strategies.
  static const bool requireTwoDeviceGateBeforeGroups = true;
  static const bool groupNetworkingEnabledV1 = false;

  /// Mobile-data policy.
  ///
  /// 1. Reuse a matching local copy whenever possible.
  /// 2. Prefer LAN/local networking for Nearby Together.
  /// 3. For Anywhere, direct P2P/STUN is preferred and TURN is fallback only.
  /// 4. A two-person peer media stream may be used as a fallback.
  /// 5. Group sessions must not fan the full movie out from the host by
  ///    default. Until group distribution is measured and proven, groups
  ///    require matching local media (or a prior Send/Nearby transfer).
  static const bool preferMatchingLocalMedia = true;
  static const bool nearbyPrefersLocalNetwork = true;
  static const bool directP2pBeforeTurn = true;
  static const bool turnIsFallbackOnly = true;
  static const bool remoteMediaStreamingIsFallback = true;
  static const bool groupRequiresMatchingLocalMediaV1 = true;
  static const bool groupRemoteMediaStreamingEnabledV1 = false;

  /// More advanced low-data ideas are intentionally staged off. They may be
  /// explored only after two-device reliability, reconnect, TURN fallback,
  /// security, and measured data usage pass without harming normal playback.
  static const bool swarmDistributionEnabledV1 = false;
  static const bool onDeviceTranscodingEnabledV1 = false;

  /// Monetization/social expansion must not complicate the first reliable
  /// Together release. OTYA proves the media experience first.
  static const bool togetherSubscriptionsEnabledV1 = false;
  static const bool togetherVoiceChatEnabledV1 = false;

  /// Before any group/network expansion is enabled, OTYA must have measured
  /// data-usage evidence rather than relying on theoretical savings.
  static const bool requireMeasuredDataUsageBeforeExpansion = true;

  /// Keep sync/chat/reaction traffic as tiny control-plane messages; media bytes
  /// stay separate from social/synchronization packets.
  static const bool keepSyncTrafficLightweight = true;

  /// Keep the ephemeral transcript bounded even during very long rooms or a
  /// noisy peer. The newest messages are retained; closing the room still
  /// removes the entire conversation.
  static const int maxConversationMessagesV1 = 250;

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
