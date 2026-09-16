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

Future<void>? _playbackPlatformInit;
bool _playbackPlatformReady = false;

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
  // Playback is the only startup subsystem that owns a long-lived Android
  // foreground service. Register a recovery callback before the first attempt:
  // if release timing/platform startup causes that attempt to fail, the next
  // Now Playing update can retry instead of leaving playback with no system UI.
  AudioHandlerSingleton.instance.configureEnsureReady(_ensurePlaybackPlatform);
  await _safeBackground('playback platform', _ensurePlaybackPlatform);

  PipService.listenForNativePause(
    () => PlaybackCoordinator.instance.activePlayer?.pause(),
    () => PlaybackCoordinator.instance.activePlayer?.play(),
  );

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

Future<void> _ensurePlaybackPlatform() {
  if (_playbackPlatformReady || AudioHandlerSingleton.instance.isReady) {
    _playbackPlatformReady = true;
    return Future<void>.value();
  }

  final existing = _playbackPlatformInit;
  if (existing != null) return existing;

  final attempt = _initPlaybackPlatformOnce();
  _playbackPlatformInit = attempt;
  unawaited(
    attempt.then<void>(
      (_) {
        _playbackPlatformReady = true;
      },
      onError: (Object _, StackTrace __) {
        // _safeBackground/ensureReady report the actual failure. Keep the
        // service retryable for the next media event.
      },
    ).whenComplete(() {
      if (identical(_playbackPlatformInit, attempt)) {
        _playbackPlatformInit = null;
      }
    }),
  );
  return attempt;
}

Future<void> _initPlaybackPlatformOnce() async {
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
      // Music must retain Android foreground-service protection after Otya
      // leaves the screen. A dismissible media notification can remove that
      // protection on OEM builds and stop playback minutes later.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_notification',
      notificationColor: AppColors.brandBlue,
      androidShowNotificationBadge: false,
      // Artwork is resolved asynchronously by MediaNotificationService. Do not
      // let a file/content URI decode delay or prevent the core MediaSession
      // notification and lock-screen controls from becoming available.
      preloadArtwork: false,
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
