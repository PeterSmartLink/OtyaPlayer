import 'dart:ffi';

/// Values that define the installed Otya application and must stay stable
/// across environments. These are safe to compile into the APK.
abstract final class AppContract {
  static const String appName = 'Otya';
  static const String appPackageId = 'com.otyaplayer.app';

  /// Otya's current authentication contract. The server is authoritative;
  /// keeping the client copy centralized prevents UI drift.
  static const int otpLength = 5;
  static const String otpExample = 'A1234';
  static final RegExp otpPattern = RegExp(r'^[A-Z][0-9]{4}$');

  /// Supported app UI locales. Language content belongs in ARB files, not here.
  static const String englishLocale = 'en';
  static const String lugandaLocale = 'lg';
}

/// Public, non-secret configuration that may change between releases or
/// environments. These values can be overridden with --dart-define.
///
/// IMPORTANT: --dart-define is configuration, not secret storage. Anything the
/// mobile app receives at runtime can ultimately be extracted from the APK or
/// process, so private credentials must remain on Cloudflare/server-side only.
abstract final class Environment {
  static const String workerUrl = String.fromEnvironment(
    'WORKER_URL',
    defaultValue: 'https://petersmartlink.com',
  );

  static const String publicSiteUrl = String.fromEnvironment(
    'PUBLIC_SITE_URL',
    defaultValue: 'https://petersmartlink.com',
  );

  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@petersmartlink.com',
  );

  // Compatibility aliases used throughout the current app.
  static const String appName = AppContract.appName;
  static const String appPackageId = AppContract.appPackageId;
  static const String websiteUrl = publicSiteUrl;

  // Canonical online API endpoints. Keep this list small: each online job has
  // one owner, while local playback/scanning continue without these services.
  static const String apiCrashUrl = '$workerUrl/api/crash-report';
  static const String checkUpdateUrl = '$workerUrl/check-update';
  static const String apiVersionUrl = '$workerUrl/api/version';
  static const String apiDeviceUrl = '$workerUrl/api/device';
  static const String apiFeedbackUrl = '$workerUrl/api/feedback';
  static const String latestUrl = '$workerUrl/latest';

  static const String arm64DownloadUrl = '$workerUrl/apk/arm64';
  static const String arm32DownloadUrl = '$workerUrl/apk/arm32';
  static const String downloadUrl = '$workerUrl/download/otya-player';
  static const String docsUrl = String.fromEnvironment(
    'DOCS_URL',
    defaultValue: 'https://docs.petersmartlink.com',
  );
  static const String authUrl = '$workerUrl/auth';
  static const String appConfigUrl = '$workerUrl/api/app-config';
  static const String themesUrl = '$workerUrl/api/themes';
  static const String downloadPageUrl = '$publicSiteUrl/download/otya-player';

  /// Self-installing APK updates are opt-in. Keep disabled by default so a
  /// release cannot accidentally enable installer behavior.
  static const bool selfUpdateEnabled =
      bool.fromEnvironment('SELF_UPDATE', defaultValue: false);

  /// ABI used by update selection and backend device registration.
  ///
  /// A non-empty APP_ARCH remains an explicit build/test override. Normal
  /// production APKs detect the ABI they are actually running on because both
  /// split APKs otherwise share the same Dart compile-time default.
  static String get appArch {
    const override = String.fromEnvironment('APP_ARCH', defaultValue: '');
    if (override.isNotEmpty) return override;

    final abi = Abi.current();
    if (abi == Abi.androidArm) return 'arm32';
    if (abi == Abi.androidArm64) return 'arm64';

    // Keep emulator/development values truthful instead of silently claiming
    // arm64 on an unsupported architecture.
    return abi.toString();
  }
}
