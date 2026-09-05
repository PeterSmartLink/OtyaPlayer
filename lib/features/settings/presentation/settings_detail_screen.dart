import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/services/custom_theme_manager.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/update_dialog.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../settings_provider.dart';

/// Otya preferences.
///
/// This screen intentionally exposes only settings that have a real runtime
/// owner. Legacy controls that no longer affect playback are not shown.
class SettingsDetailScreen extends ConsumerWidget {
  const SettingsDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return WallpaperScaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/myspace'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 28,
        ),
        children: [
          const _SectionTitle('Appearance'),
          _Card(children: [
            _NavTile(
              icon: Icons.palette_rounded,
              title: 'Personalize',
              subtitle: 'Light, dark, AMOLED, themes and seasonal artwork',
              onTap: () => context.push('/theme'),
            ),
            const _Line(),
            _NavTile(
              icon: Icons.wallpaper_rounded,
              title: 'Choose wallpaper',
              subtitle: 'Use a photo from this device',
              onTap: () => _chooseWallpaper(context),
            ),
            const _Line(),
            _NavTile(
              icon: Icons.hide_image_rounded,
              title: 'Remove wallpaper',
              subtitle: 'Return to the selected Otya theme background',
              onTap: () => _removeWallpaper(context),
            ),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Playback'),
          _Card(children: [
            _SwitchTile(
              icon: Icons.history_rounded,
              title: 'Resume playback',
              subtitle: 'Continue from the last saved position',
              value: settings.autoResume,
              onChanged: notifier.setAutoResume,
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.picture_in_picture_alt_rounded,
              title: 'Automatic picture-in-picture',
              subtitle: 'Enter PiP when a supported video leaves the foreground',
              value: settings.autoPip,
              onChanged: notifier.setAutoPip,
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.screen_rotation_alt_rounded,
              title: 'Lock video orientation',
              subtitle: 'Keep the selected orientation while a video is playing',
              value: settings.orientationLocked,
              onChanged: notifier.setOrientationLocked,
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.skip_next_rounded,
              title: 'Continuous playback',
              subtitle: 'Continue to the next item in the current queue',
              value: settings.continuousPlayback,
              onChanged: notifier.setContinuousPlayback,
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.closed_caption_rounded,
              title: 'Auto-load subtitles',
              subtitle: 'Use compatible subtitle tracks when available',
              value: settings.autoLoadSubtitles,
              onChanged: notifier.setAutoLoadSubtitles,
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.phone_in_talk_rounded,
              title: 'Pause during calls',
              subtitle: 'Pause media when Android reports an active phone call',
              value: settings.pauseDuringCalls,
              onChanged: notifier.setPauseDuringCalls,
            ),
            const _Line(),
            _SpeedTile(
              value: settings.playbackSpeed,
              onChanged: notifier.setPlaybackSpeed,
            ),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Privacy & device'),
          _Card(children: [
            _NavTile(
              icon: Icons.lock_rounded,
              title: 'Private',
              subtitle: 'Protected local media and authentication',
              onTap: () => context.push('/vault'),
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.phonelink_lock_rounded,
              title: 'App Lock',
              subtitle: 'Require your Android screen lock, fingerprint or face after Otya leaves the foreground',
              value: settings.appLockEnabled,
              onChanged: (enabled) => _setAppLock(context, notifier, enabled),
            ),
            const _Line(),
            _SwitchTile(
              icon: Icons.manage_search_rounded,
              title: 'Search history',
              subtitle: 'Remember recent Otya searches on this device',
              value: settings.searchHistory,
              onChanged: notifier.setSearchHistory,
            ),
            const _Line(),
            _NavTile(
              icon: Icons.notifications_active_rounded,
              title: 'Notifications',
              subtitle: 'Completed tasks, security notices and Otya updates',
              onTap: () async {
                HapticFeedback.selectionClick();
                final granted = await NotificationService.instance.requestPermission();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      granted
                          ? 'Notifications are enabled.'
                          : 'Notification permission was not granted.',
                    ),
                  ),
                );
              },
            ),
            const _Line(),
            _NavTile(
              icon: Icons.settings_applications_rounded,
              title: 'Android app permissions',
              subtitle: 'Review media, notification and device permissions',
              onTap: () => openAppSettings(),
            ),
            const _Line(),
            _NavTile(
              icon: Icons.storage_rounded,
              title: 'Storage',
              subtitle: 'Inspect Otya media and device storage',
              onTap: () => context.push('/settings/storage'),
            ),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Otya'),
          _Card(children: [
            _NavTile(
              icon: Icons.system_update_rounded,
              title: 'Check for updates',
              subtitle: 'Check the canonical Otya release service',
              onTap: () async {
                HapticFeedback.selectionClick();
                await UpdateDialog.checkAndShow(context, forceCheck: true);
              },
            ),
            const _Line(),
            _NavTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              subtitle: 'How Otya handles account and service data',
              onTap: () => context.push('/privacy'),
            ),
            const _Line(),
            _NavTile(
              icon: Icons.info_outline_rounded,
              title: 'About Otya',
              subtitle: 'Version, product information and legal links',
              onTap: () => context.push('/about'),
            ),
          ]),
        ],
      ),
    );
  }

  static Future<void> _setAppLock(
    BuildContext context,
    SettingsNotifier notifier,
    bool enabled,
  ) async {
    if (!enabled) {
      notifier.setAppLock(false);
      return;
    }

    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      if (!context.mounted) return;
      if (!supported) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set an Android screen lock, fingerprint or face authentication before enabling App Lock.',
            ),
          ),
        );
        return;
      }

      final verified = await auth.authenticate(
        localizedReason: 'Verify your device authentication to enable Otya App Lock',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!context.mounted) return;
      if (verified) {
        notifier.setAppLock(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App Lock enabled.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App Lock was not enabled because authentication was cancelled.'),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Device authentication is unavailable. Check Android security settings and try again.',
          ),
        ),
      );
    }
  }

  static Future<void> _chooseWallpaper(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;
      await CustomThemeManager.instance.setWallpaper(picked.path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallpaper updated.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Otya could not use that image.')),
      );
    }
  }

  static Future<void> _removeWallpaper(BuildContext context) async {
    await CustomThemeManager.instance.clearWallpaper();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wallpaper removed.')),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(children: children),
      );
}

class _Line extends StatelessWidget {
  const _Line();
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 58,
        color: AppColors.borderOf(context),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        leading: Icon(icon, color: AppColors.accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, maxLines: 2),
        trailing: const Icon(Icons.chevron_right_rounded),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        value: value,
        onChanged: (next) {
          HapticFeedback.selectionClick();
          onChanged(next);
        },
        secondary: Icon(icon, color: AppColors.accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  static const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.speed_rounded, color: AppColors.accent),
        title: const Text(
          'Default playback speed',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Used when a player starts a new session'),
        trailing: DropdownButton<double>(
          value: speeds.contains(value) ? value : 1.0,
          underline: const SizedBox.shrink(),
          items: speeds
              .map(
                (speed) => DropdownMenuItem(
                  value: speed,
                  child: Text('$speed×'),
                ),
              )
              .toList(growable: false),
          onChanged: (next) {
            if (next == null) return;
            HapticFeedback.selectionClick();
            onChanged(next);
          },
        ),
      );
}
