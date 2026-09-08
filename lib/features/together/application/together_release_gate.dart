/// Release gate for the user-facing Watch Together capability.
///
/// The current OTYA v1 product contract keeps Together private until its
/// two-device, cross-network, TURN, sync/reconnect, data-usage, security and
/// offline-playback gates pass. Internal validation builds may opt in with:
///
///   --dart-define=OTYA_ENABLE_WATCH_TOGETHER=true
///
/// Public/release builds remain disabled by default.
abstract final class TogetherReleaseGate {
  static bool get isPubliclyEnabled => const bool.fromEnvironment(
        'OTYA_ENABLE_WATCH_TOGETHER',
        defaultValue: false,
      );
}
