import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/media_item.dart';
import '../core/services/remote_control_service.dart';
import '../features/air_drop/presentation/air_drop_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/downloads/presentation/downloads_screen.dart';
import '../features/music/presentation/music_tab_screen.dart';
import '../features/my_space/presentation/folder_browser_screen.dart'
    show FolderBrowserScreen, FolderDetailScreen;
import '../features/my_space/presentation/my_space_hub_screen.dart';
import '../features/my_space/presentation/playback_history_screen.dart';
import '../features/my_space/presentation/usage_stats_dashboard.dart';
import '../features/player/presentation/audio_player_screen.dart';
import '../features/player/presentation/car_mode_screen.dart';
import '../features/player/presentation/equalizer_screen.dart';
import '../features/player/presentation/mini_player.dart';
import '../features/player/presentation/video_player_screen.dart';
import '../features/playlists/playlist_screen.dart'
    show PlaylistDetailScreenById, PlaylistsScreen;
import '../features/profile/profile_screen.dart'
    show ProfileScreen, WhatsNewScreen;
import '../features/settings/presentation/about_screen.dart';
import '../features/settings/presentation/privacy_policy_screen.dart';
import '../features/settings/presentation/settings_detail_screen.dart';
import '../features/settings/presentation/storage_analyzer_screen.dart';
import '../features/settings/presentation/theme_selection_screen.dart';
import '../features/tools/whatsapp_trimmer_screen.dart';
import '../features/vault/presentation/vault_lock_screen.dart';
import '../features/video/presentation/video_tab_screen.dart'
    show VideoFolderDetailPage, VideoTabScreen;
import '../features/webview/otya_webview_screen.dart';

CustomTransitionPage<void> _fadePage({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );

CustomTransitionPage<void> _slideUpPage({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .06),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
    );

class AppRouter {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static String? _redirect(BuildContext context, GoRouterState state) {
    final remote = RemoteControlService.instance;
    final feature = switch (state.matchedLocation) {
      '/transfer' => 'transfer',
      '/vault' => 'private',
      '/player/equalizer' => 'equalizer',
      '/tools/whatsapp' => 'whatsappTrimmer',
      _ => null,
    };
    if (feature != null && !remote.featureEnabled(feature)) return '/myspace';
    return null;
  }

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    redirect: _redirect,
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) => _fadePage(
          context: context,
          state: state,
          child: _MainShell(child: child),
        ),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => _fadePage(
              context: context,
              state: state,
              child: const VideoTabScreen(),
            ),
          ),
          GoRoute(
            path: '/music',
            pageBuilder: (context, state) => _fadePage(
              context: context,
              state: state,
              child: const MusicTabScreen(),
            ),
          ),
          GoRoute(
            path: '/myspace',
            pageBuilder: (context, state) => _fadePage(
              context: context,
              state: state,
              child: const MySpaceHubScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/downloads',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const DownloadsScreen()),
      ),
      GoRoute(path: '/support', redirect: (_, __) => '/about'),
      GoRoute(path: '/ai', redirect: (_, __) => '/about'),
      GoRoute(
        path: '/auth',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const AuthScreen()),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/auth/verify-email',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const VerifyEmailScreen(),
        ),
      ),
      GoRoute(
        path: '/transfer',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const AirDropScreen()),
      ),
      GoRoute(path: '/airdrop', redirect: (_, __) => '/transfer'),
      GoRoute(
        path: '/profile',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const ProfileScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const SettingsDetailScreen(),
        ),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const AboutScreen()),
      ),
      GoRoute(
        path: '/theme',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const ThemeSelectionScreen(),
        ),
      ),
      GoRoute(
        path: '/tools/folders',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const FolderBrowserScreen(),
        ),
      ),
      GoRoute(
        path: '/tools/folder-detail',
        pageBuilder: (c, s) {
          final args = (s.extra as Map<String, dynamic>?) ?? {};
          if (args['folderName'] is! String ||
              args['fullPath'] is! String ||
              args['items'] is! List<MediaItem>) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this folder.',
              ),
            );
          }
          return _fadePage(
            context: c,
            state: s,
            child: FolderDetailScreen(
              folderName: args['folderName'] as String,
              fullPath: args['fullPath'] as String,
              items: args['items'] as List<MediaItem>,
            ),
          );
        },
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const PlaybackHistoryScreen(),
        ),
      ),
      GoRoute(
        path: '/playlists',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const PlaylistsScreen()),
      ),
      GoRoute(
        path: '/playlist/:id',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: PlaylistDetailScreenById(
            playlistId: s.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/vault',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const VaultLockScreen()),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const PrivacyPolicyScreen(),
        ),
      ),
      GoRoute(
        path: '/whats-new',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const WhatsNewScreen()),
      ),
      GoRoute(
        path: '/video/folder',
        pageBuilder: (c, s) {
          final args = s.extra as Map<String, dynamic>?;
          if (args == null || args['name'] == null || args['items'] == null) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this folder.',
              ),
            );
          }
          return _fadePage(
            context: c,
            state: s,
            child: VideoFolderDetailPage(
              name: args['name'] as String,
              items: args['items'] as List<MediaItem>,
            ),
          );
        },
      ),
      GoRoute(
        path: '/settings/storage',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const StorageAnalyzerScreen(),
        ),
      ),
      GoRoute(
        path: '/stats',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const UsageStatsDashboard(),
        ),
      ),
      GoRoute(
        path: '/player/equalizer',
        pageBuilder: (c, s) => _fadePage(
          context: c,
          state: s,
          child: const EqualizerScreen(),
        ),
      ),
      GoRoute(
        path: '/player/video',
        pageBuilder: (c, s) {
          final item = s.extra;
          if (item is! MediaItem) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this video.',
              ),
            );
          }
          return _slideUpPage(
            context: c,
            state: s,
            child: VideoPlayerScreen(mediaItem: item),
          );
        },
      ),
      GoRoute(
        path: '/player/audio',
        pageBuilder: (c, s) {
          final extra = s.extra;
          if (extra is Map<String, dynamic>) {
            final item = extra['item'];
            if (item is! MediaItem) {
              return _fadePage(
                context: c,
                state: s,
                child: const _RouteErrorScreen(
                  message: 'Could not open this song.',
                ),
              );
            }
            return _slideUpPage(
              context: c,
              state: s,
              child: AudioPlayerScreen(
                mediaItem: item,
                resumeOnly: extra['resumeOnly'] as bool? ?? false,
              ),
            );
          }
          if (extra is! MediaItem) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this song.',
              ),
            );
          }
          return _slideUpPage(
            context: c,
            state: s,
            child: AudioPlayerScreen(mediaItem: extra),
          );
        },
      ),
      GoRoute(
        path: '/player/car-mode',
        pageBuilder: (c, s) =>
            _fadePage(context: c, state: s, child: const CarModeScreen()),
      ),
      GoRoute(
        path: '/music/folder',
        pageBuilder: (c, s) {
          final args = s.extra as Map<String, dynamic>?;
          if (args == null || args['name'] == null || args['items'] == null) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this folder.',
              ),
            );
          }
          return _fadePage(
            context: c,
            state: s,
            child: MusicFolderDetailPage(
              name: args['name'] as String,
              items: args['items'] as List<MediaItem>,
            ),
          );
        },
      ),
      GoRoute(
        path: '/music/album',
        pageBuilder: (c, s) {
          final args = s.extra as Map<String, dynamic>?;
          if (args == null || args['name'] == null || args['items'] == null) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this album.',
              ),
            );
          }
          return _fadePage(
            context: c,
            state: s,
            child: MusicAlbumDetailPage(
              name: args['name'] as String,
              items: args['items'] as List<MediaItem>,
            ),
          );
        },
      ),
      GoRoute(
        path: '/music/artist',
        pageBuilder: (c, s) {
          final args = s.extra as Map<String, dynamic>?;
          if (args == null || args['name'] == null || args['items'] == null) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Could not open this artist.',
              ),
            );
          }
          return _fadePage(
            context: c,
            state: s,
            child: MusicArtistDetailPage(
              name: args['name'] as String,
              items: args['items'] as List<MediaItem>,
            ),
          );
        },
      ),
      GoRoute(
        path: '/webview',
        pageBuilder: (c, s) {
          final args = s.extra as Map<String, dynamic>? ?? {};
          return _fadePage(
            context: c,
            state: s,
            child: OtyaWebViewScreen(
              url: args['url'] as String? ??
                  'https://petersmartlink.com/otya-player',
              title: args['title'] as String?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/tools/whatsapp',
        pageBuilder: (c, s) {
          final item = s.extra;
          if (item is! MediaItem) {
            return _fadePage(
              context: c,
              state: s,
              child: const _RouteErrorScreen(
                message: 'Choose a video before opening Trim Video.',
              ),
            );
          }
          return _fadePage(
            context: c,
            state: s,
            child: WhatsAppTrimmerScreen(mediaItem: item),
          );
        },
      ),
    ],
  );
}

class _MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  static const _routes = ['/', '/music', '/myspace'];
  static const _wideBreakpoint = 600.0;

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    GoRouter.of(context).go(_routes[index]);
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/music')) return 1;
    if (location.startsWith('/myspace')) return 2;
    return 0;
  }

  Widget _miniPlayer() => Consumer(
        builder: (context, ref, _) {
          final hasMini = ref.watch(miniPlayerItemProvider) != null;
          return hasMini
              ? const RepaintBoundary(child: MiniPlayer())
              : const SizedBox.shrink();
        },
      );

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: currentIndex,
                    labelType: NavigationRailLabelType.all,
                    minWidth: 80,
                    onDestinationSelected: _onTap,
                    leading: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/icons/play_store_512.png',
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.video_library_outlined),
                        selectedIcon: Icon(Icons.video_library_rounded),
                        label: Text('Video'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music_rounded),
                        label: Text('Music'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: Text('Me'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: widget.child),
                        _miniPlayer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: widget.child,
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniPlayer(),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: .55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? .30
                              : .10,
                        ),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(27),
                    child: NavigationBar(
                      selectedIndex: currentIndex,
                      onDestinationSelected: _onTap,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.video_library_outlined),
                          selectedIcon: Icon(Icons.video_library_rounded),
                          label: 'Video',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.library_music_outlined),
                          selectedIcon: Icon(Icons.library_music_rounded),
                          label: 'Music',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.person_outline_rounded),
                          selectedIcon: Icon(Icons.person_rounded),
                          label: 'Me',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RouteErrorScreen extends StatelessWidget {
  final String message;
  const _RouteErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OTYA')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 36),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to OTYA'),
                ),
              ],
            ),
          ),
        ),
      );
}
