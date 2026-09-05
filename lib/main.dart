import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app/app.dart';
import 'app/theme/app_colors.dart';
import 'core/database/otya_database.dart';
import 'core/services/audio_handler.dart';
import 'core/services/audio_session_service.dart';
import 'core/services/cache_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/crash_reporter.dart';
import 'core/services/device_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/firebase_platform_service.dart';
import 'core/services/media_notification_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/pip_service.dart';
import 'core/services/playback_coordinator.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/storage_folder_service.dart';
import 'core/services/update_service.dart';
import 'features/settings/settings_provider.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await CrashReporter.instance.init();

    final settingsNotifier = SettingsNotifier(const AppSettings());

    runApp(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => settingsNotifier),
        ],
        child: const OtyaPlayerApp(),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapAfterFirstFrame(settingsNotifier));
    });
  }, (error, stack) {
    debugPrint('[ZoneError] $error\n$stack');
    CrashReporter.instance.report(error, stack);
  });
}

Future<void> _bootstrapAfterFirstFrame(SettingsNotifier settingsNotifier) async {
  // The app gate owns the one startup settings read because privacy/App Lock
  // must be known before protected content is revealed. Background services
  // reuse that same result instead of opening SharedPreferences a second time.
  final savedSettings = await settingsNotifier.startupHydration;

  var databaseReady = false;
  try {
    databaseReady = await _initDatabase();
  } catch (e, st) {
    debugPrint('[Database] init failed: $e\n$st');
    CrashReporter.instance.report(e, st);
  }

  await _initBackground(savedSettings, databaseReady);
}

Future<bool> _initDatabase() async {
  try {
    await OtyaDatabase.instance.init();
    return true;
  } catch (e, st) {
    debugPrint('[OtyaDB] Init error: $e\n$st');
    CrashReporter.instance.report(e, st);
    return false;
  }
}

Future<void> _initBackground(
  AppSettings savedSettings,
  bool databaseReady,
) async {
  // Playback remains the strict first dependency so immediate playback always
  // has a real Android MediaSession and foreground-service notification.
  await _safeBackground('playback platform', _initPlaybackPlatform);

  PipService.listenForNativePause(
    () => PlaybackCoordinator.instance.activePlayer?.pause(),
    () => PlaybackCoordinator.instance.activePlayer?.play(),
  );

  // These initializers are independent after playback setup. Run them together
  // so readiness is bounded by the slowest service rather than their sum.
  final notificationsReady =
      _safeBackground('notifications', _initNotifications);
  final storageReady =
      _safeBackground('storage', StorageFolderService.instance.ensureCreated);
  final connectivityReady =
      _safeBackground('connectivity', ConnectivityService.instance.init);
  final cacheReady = _safeBackground('cache', CacheService.instance.init);
  final audioSessionReady = _safeBackground(
    'audio session',
    () => AudioSessionService.instance.init(
      pauseDuringCalls: savedSettings.pauseDuringCalls,
    ),
  );
  final firebaseReady = _safeBackground(
    'Firebase platform',
    FirebasePlatformService.instance.initOptionalServices,
  );

  if (databaseReady) {
    unawaited(
      _safeBackground('device registration', DeviceService.instance.registerIfNeeded),
    );
  }

  unawaited(
    cacheReady.then(
      (_) => _safeBackground(
        'cache eviction',
        CacheService.instance.evictExpired,
      ),
    ),
  );
  unawaited(
    connectivityReady.then(
      (_) => _safeBackground(
        'update check',
        UpdateService.instance.checkAndNotify,
      ),
    ),
  );
  unawaited(
    firebaseReady.then(
      (_) => _safeBackground('FCM', FcmService.instance.init),
    ),
  );

  await Future.wait<void>([
    notificationsReady,
    storageReady,
    connectivityReady,
    cacheReady,
    audioSessionReady,
    firebaseReady,
  ]);
}

Future<void> _initPlaybackPlatform() async {
  MediaKit.ensureInitialized();

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));

  final audioHandler = await AudioService.init(
    builder: () => OtyaAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.otyaplayer.app.audio',
      androidNotificationChannelName: 'Otya — Now Playing',
      // Keeping the foreground service alive while paused already makes the
      // media notification ongoing. audio_service rejects explicitly enabling
      // both behaviours at once.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_notification',
      notificationColor: AppColors.brandBlue,
      androidShowNotificationBadge: false,
      preloadArtwork: true,
    ),
  );
  AudioHandlerSingleton.instance.handler = audioHandler;
}

Future<void> _safeBackground(
  String name,
  Future<void> Function() task,
) async {
  try {
    await task();
  } catch (e, st) {
    debugPrint('[Background:$name] Error: $e\n$st');
    CrashReporter.instance.report(e, st);
  }
}

Future<void> _initNotifications() async {
  await _safeBackground(
    'notification service',
    NotificationService.instance.init,
  );
  await _safeBackground(
    'media notifications',
    MediaNotificationService.instance.init,
  );
  await _safeBackground(
    'push notifications',
    PushNotificationService.instance.init,
  );
}
