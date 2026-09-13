/// Release gate for the user-facing Watch Together capability.
///
/// Together is part of the public OTYA product. Public and release builds are
/// enabled by default. The environment flag remains as an emergency rollback
/// switch so a specifically-built recovery artifact can disable the feature
/// without deleting the implementation.
///
///   --dart-define=OTYA_ENABLE_WATCH_TOGETHER=false
///
abstract final class TogetherReleaseGate {
  static bool get isPubliclyEnabled => const bool.fromEnvironment(
        'OTYA_ENABLE_WATCH_TOGETHER',
        defaultValue: true,
      );
}
