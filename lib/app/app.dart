import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/custom_theme_manager.dart';
import '../core/services/notification_service.dart';
import '../core/services/remote_control_service.dart';
import '../core/widgets/announcement_dialog.dart';
import '../core/widgets/remote_control_gate.dart';
import '../core/widgets/update_dialog.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/app_lock_screen.dart';
import '../features/settings/settings_provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/widgets/otya_logo.dart';
import 'router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

class OtyaPlayerApp extends ConsumerStatefulWidget {
  const OtyaPlayerApp({super.key});

  @override
  ConsumerState<OtyaPlayerApp> createState() => _OtyaPlayerAppState();
}

class _OtyaPlayerAppState extends ConsumerState<OtyaPlayerApp> {
  bool _onboardingDone = false;
  bool _checking = true;
  bool _startupDialogsScheduled = false;
  Timer? _startupDialogTimer;

  @override
  void initState() {
    super.initState();

    _hydrateStartupPrivacyAndOnboarding();
    unawaited(_loadLocalVisualTheme());

    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_startRemoteServicesAfterFirstFrame());
      _scheduleStartupDialogs();
    });
  }

  @override
  void dispose() {
    _startupDialogTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalVisualTheme() async {
    try {
      await CustomThemeManager.instance.load();
    } catch (_) {}
  }

  Future<void> _startRemoteServicesAfterFirstFrame() async {
    try {
      await RemoteControlService.instance.init();
    } catch (_) {}
    unawaited(
      CustomThemeManager.instance.refreshSeasonalTheme().catchError((_) {}),
    );
  }

  void _scheduleStartupDialogs() {
    if (!mounted ||
        _checking ||
        !_onboardingDone ||
        _startupDialogsScheduled) {
      return;
    }

    _startupDialogsScheduled = true;
    _startupDialogTimer?.cancel();
    _startupDialogTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_showStartupDialogsSequentially());
    });
  }

  Future<void> _showStartupDialogsSequentially() async {
    try {
      final announcementContext = AppRouter.navigatorKey.currentContext;
      if (!mounted ||
          announcementContext == null ||
          !announcementContext.mounted) {
        return;
      }

      // Announcements have priority and must finish before an update prompt is
      // considered. Each dialog receives a fresh root-Navigator context so no
      // BuildContext is carried across the async gap between the two modals.
      await AnnouncementDialog.showIfPending(announcementContext);
      if (!mounted) return;

      await Future<void>.delayed(const Duration(seconds: 2));
      final updateContext = AppRouter.navigatorKey.currentContext;
      if (!mounted || updateContext == null || !updateContext.mounted) return;
      await UpdateDialog.checkAndShow(updateContext);
    } catch (_) {
      // Startup notices are non-critical. Local playback and navigation must
      // remain available even when a remote announcement/update check fails.
    }
  }

  Future<void> _hydrateStartupPrivacyAndOnboarding() async {
    try {
      // Start the onboarding preference read at the same time, but keep the
      // privacy settings load explicit: App Lock must be hydrated before the
      // router can be revealed.
      final prefsFuture = SharedPreferences.getInstance();
      final savedSettings = await AppSettings.load();
      final prefs = await prefsFuture;
      if (!mounted) return;
      ref.read(settingsProvider.notifier).hydrate(savedSettings);
      setState(() {
        _onboardingDone = prefs.getBool('onboarding_done') ?? false;
        _checking = false;
      });
      _scheduleStartupDialogs();
    } catch (_) {
      // The preference/settings reads can finish after the root widget has
      // been disposed (for example during an activity recreation). Riverpod's
      // ref and widget state must not be touched after that point.
      if (!mounted) return;
      ref.read(settingsProvider.notifier).hydrate(const AppSettings());
      setState(() {
        _onboardingDone = true;
        _checking = false;
      });
      _scheduleStartupDialogs();
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _onboardingDone = true);
    _scheduleStartupDialogs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_requestNotificationPermissionSafely());
    });
  }

  Future<void> _requestNotificationPermissionSafely() async {
    try {
      await NotificationService.instance.requestPermission();
    } catch (_) {}
  }

  ThemeMode _materialThemeMode(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.dark || AppThemeMode.amoled => ThemeMode.dark,
      };

  ThemeData _darkTheme(AppThemeMode mode) {
    if (mode == AppThemeMode.amoled) {
      return AppTheme.dark.copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppTheme.dark.appBarTheme.copyWith(
          backgroundColor: Colors.black,
        ),
      );
    }
    return AppTheme.dark;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    if (_checking) {
      return MaterialApp(
        title: 'Otya',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: _darkTheme(settings.themeMode),
        themeMode: _materialThemeMode(settings.themeMode),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OtyaLogo(iconOnly: true, fontSize: 68),
                const SizedBox(height: 16),
                Text(
                  'Otya',
                  style: TextStyle(
                    color: AppColors.textPrimaryOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 26),
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        CustomThemeManager.instance,
        RemoteControlService.instance,
      ]),
      builder: (context, _) {
        final themeManager = CustomThemeManager.instance;
        final hasArtwork =
            themeManager.hasImageWallpaper || themeManager.storyTheme != null;
        final baseLight = AppTheme.light;
        final baseDark = _darkTheme(settings.themeMode);
        final lightTheme = hasArtwork
            ? baseLight.copyWith(scaffoldBackgroundColor: Colors.transparent)
            : baseLight;
        final darkTheme = hasArtwork
            ? baseDark.copyWith(scaffoldBackgroundColor: Colors.transparent)
            : baseDark;

        return MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: _materialThemeMode(settings.themeMode),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: AppRouter.router,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final overlay = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarContrastEnforced: false,
            );

            Widget wrappedChild = child ?? const SizedBox.shrink();
            final wallpaperDecoration = themeManager.wallpaperDecoration;
            if (wallpaperDecoration != null) {
              wrappedChild = Container(
                decoration: BoxDecoration(image: wallpaperDecoration),
                child: wrappedChild,
              );
            }

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlay,
              child: AppLockGate(
                child: RemoteControlGate(
                  child: Stack(
                    children: [
                      wrappedChild,
                      if (!_onboardingDone)
                        OnboardingOverlay(onDone: _completeOnboarding),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
