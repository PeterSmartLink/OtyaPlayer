import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/services/ffmpeg_service.dart';
import '../../../core/services/remote_control_service.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../search/smart_search_sheet.dart';
import 'providers/my_space_provider.dart';

class MySpaceHubScreen extends ConsumerWidget {
  const MySpaceHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(displayNameProvider);
    final photoUrl = ref.watch(photoUrlProvider);
    final remote = RemoteControlService.instance;

    return WallpaperScaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MeHeader(
                displayName: displayName,
                photoUrl: photoUrl,
                onSearch: () => SmartSearchSheet.show(context),
                onProfile: () => context.push('/profile'),
              ),
            ),
            const SliverToBoxAdapter(child: _SectionLabel('Quick actions')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _PrimaryAction(
                        icon: Icons.send_rounded,
                        title: 'Send',
                        subtitle: 'Nearby sharing',
                        enabled: remote.featureEnabled('transfer', fallback: true),
                        onTap: () => context.push('/transfer'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PrimaryAction(
                        icon: Icons.folder_open_rounded,
                        title: 'Files',
                        subtitle: 'Browse folders',
                        onTap: () => context.push('/tools/folders'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PrimaryAction(
                        icon: Icons.lock_outline_rounded,
                        title: 'Private',
                        subtitle: 'Protected media',
                        enabled: remote.featureEnabled('private', fallback: true),
                        onTap: () => context.push('/vault'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _SectionLabel('Library & activity')),
            SliverToBoxAdapter(
              child: _RowGroup(
                children: [
                  _ActionRow(
                    icon: Icons.queue_music_rounded,
                    title: 'Playlists',
                    subtitle: 'Open your saved local playlists',
                    onTap: () => context.push('/playlists'),
                  ),
                  _ActionRow(
                    icon: Icons.history_rounded,
                    title: 'History',
                    subtitle: 'Recently played media on this device',
                    onTap: () => context.push('/history'),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            const SliverToBoxAdapter(child: _SectionLabel('Tools & settings')),
            SliverToBoxAdapter(
              child: _RowGroup(
                children: [
                  _ActionRow(
                    icon: Icons.tune_rounded,
                    title: 'Tools',
                    subtitle: 'Convert, trim and adjust media',
                    onTap: () => _showTools(context, ref),
                  ),
                  _ActionRow(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    subtitle: 'Theme and visual preferences',
                    onTap: () => context.push('/theme'),
                  ),
                  _ActionRow(
                    icon: Icons.storage_rounded,
                    title: 'Storage',
                    subtitle: 'Media scanning and device storage',
                    onTap: () => context.push('/settings/storage'),
                  ),
                  _ActionRow(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    subtitle: 'Playback, privacy, permissions and updates',
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            const SliverToBoxAdapter(child: _SectionLabel('Account')),
            SliverToBoxAdapter(
              child: _RowGroup(
                children: [
                  _ActionRow(
                    icon: Icons.account_circle_outlined,
                    title: 'OTYA Account',
                    subtitle: 'Profile, sign-in, security and backup',
                    onTap: () => context.push('/profile'),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            const SliverToBoxAdapter(child: _SectionLabel('Product')),
            SliverToBoxAdapter(
              child: _RowGroup(
                children: [
                  _ActionRow(
                    icon: Icons.info_outline_rounded,
                    title: 'About OTYA',
                    subtitle: 'Version, privacy, terms and product information',
                    onTap: () => context.push('/about'),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 28),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showConverter(BuildContext context, WidgetRef ref) async {
    final videos = (ref.read(mediaLibraryProvider).valueOrNull ?? const <MediaItem>[])
        .where((item) => item.isVideo)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await _showMediaActionSheet(
      context,
      title: 'Convert video to audio',
      subtitle: 'Choose a video. OTYA extracts its existing audio locally without uploading the file.',
      items: videos,
      actionIcon: Icons.music_note_rounded,
      actionLabel: 'Extract audio',
      run: (item, progress) => FfmpegService.instance.extractAudio(
        videoPath: item.filePath,
        onProgress: progress,
      ),
      onFinished: () => ref.read(mediaLibraryProvider.notifier).backgroundRefresh(),
    );
  }

  static Future<void> _showTools(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.cardOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Media tools', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            const Text(
              'Work with media on this device. OTYA will show progress and where the result is saved.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            _ActionRow(
              icon: Icons.transform_rounded,
              title: 'Convert video to audio',
              subtitle: 'Extract a video’s audio track',
              onTap: () {
                Navigator.pop(sheetContext);
                _showConverter(context, ref);
              },
            ),
            _ActionRow(
              icon: Icons.content_cut_rounded,
              title: 'Trim video',
              subtitle: 'Create a shorter clip',
              onTap: () {
                Navigator.pop(sheetContext);
                _showTrimPicker(context, ref);
              },
            ),
            _ActionRow(
              icon: Icons.graphic_eq_rounded,
              title: 'Equalizer',
              subtitle: 'Tune audio playback',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/player/equalizer');
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showTrimPicker(BuildContext context, WidgetRef ref) async {
    final videos = (ref.read(mediaLibraryProvider).valueOrNull ?? const <MediaItem>[])
        .where((item) => item.isVideo)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await _showMediaActionSheet(
      context,
      title: 'Trim video',
      subtitle: 'Choose a video to create a 30-second clip from its beginning. Custom-range trimming remains available in the player.',
      items: videos,
      actionIcon: Icons.content_cut_rounded,
      actionLabel: 'Trim 30 seconds',
      run: (item, progress) {
        final duration = item.duration?.inSeconds.toDouble() ?? 30;
        return FfmpegService.instance.trimVideo(
          videoPath: item.filePath,
          startSec: 0,
          endSec: duration.clamp(1, 30),
          onProgress: progress,
        );
      },
      onFinished: () => ref.read(mediaLibraryProvider.notifier).backgroundRefresh(),
    );
  }

  static Future<void> _showMediaActionSheet(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<MediaItem> items,
    required IconData actionIcon,
    required String actionLabel,
    required Future<String?> Function(MediaItem item, void Function(double) progress) run,
    required Future<void> Function() onFinished,
  }) async {
    String? busyId;
    String? result;
    String? error;
    double progress = 0;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.cardOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                    if (busyId != null) ...[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(value: progress > 0 ? progress : null),
                      const SizedBox(height: 7),
                      const Text('Processing on this device…', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                    if (result != null) ...[
                      const SizedBox(height: 12),
                      _ResultBanner(
                        icon: Icons.check_circle_outline_rounded,
                        text: 'Saved ${result!.replaceAll('\\', '/').split('/').last}',
                        success: true,
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      _ResultBanner(
                        icon: Icons.error_outline_rounded,
                        text: error!,
                        success: false,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: Text(
                            'No local videos are available yet. Add or scan a video, then try again.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final active = busyId == item.id;
                          return ListTile(
                            enabled: busyId == null,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(Icons.movie_outlined, color: AppColors.accent),
                            ),
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item.formattedDuration} · ${item.formattedSize}'),
                            trailing: active
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(actionIcon, color: AppColors.accent),
                            onTap: busyId != null
                                ? null
                                : () async {
                                    setState(() {
                                      busyId = item.id;
                                      result = null;
                                      error = null;
                                      progress = .05;
                                    });
                                    try {
                                      final output = await run(item, (value) {
                                        if (sheetContext.mounted) {
                                          setState(() => progress = value.clamp(0, 1));
                                        }
                                      });
                                      if (!sheetContext.mounted) return;
                                      if (output != null) {
                                        await onFinished();
                                        if (!sheetContext.mounted) return;
                                        setState(() => result = output);
                                      } else {
                                        setState(() {
                                          error = 'OTYA could not process this file. The format or codec may not be supported by this tool yet. Try another file or open it in the player first.';
                                        });
                                      }
                                    } catch (_) {
                                      if (!sheetContext.mounted) return;
                                      setState(() {
                                        error = 'Processing stopped before a result could be saved. Check that the source file is still available and try again.';
                                      });
                                    } finally {
                                      if (sheetContext.mounted) {
                                        setState(() {
                                          busyId = null;
                                          progress = 0;
                                        });
                                      }
                                    }
                                  },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeHeader extends StatelessWidget {
  const _MeHeader({
    required this.displayName,
    required this.photoUrl,
    required this.onSearch,
    required this.onProfile,
  });

  final String? displayName;
  final String? photoUrl;
  final VoidCallback onSearch;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final name = displayName?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Me',
                  style: TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1),
                ),
                const SizedBox(height: 7),
                Text(
                  name?.isNotEmpty == true ? 'Good to see you, $name' : 'Your media, tools and OTYA account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Search OTYA',
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Open OTYA Account',
            child: GestureDetector(
              onTap: onProfile,
              child: _Avatar(photoUrl: photoUrl, name: displayName),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : .45,
        child: Material(
          color: AppColors.cardOf(context).withValues(alpha: .9),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 122),
              padding: const EdgeInsets.fromLTRB(12, 15, 10, 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: AppColors.accent),
                  ),
                  const Spacer(),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, height: 1.25, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.icon, required this.text, required this.success});
  final IconData icon;
  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (success ? Colors.green : Theme.of(context).colorScheme.error).withValues(alpha: .09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: success ? Colors.green : Theme.of(context).colorScheme.error),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.name});
  final String? photoUrl;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final initial = (name?.trim().isNotEmpty == true ? name!.trim()[0] : 'O').toUpperCase();
    return CircleAvatar(
      radius: 21,
      backgroundColor: AppColors.cardOf(context),
      backgroundImage: photoUrl?.trim().isNotEmpty == true ? CachedNetworkImageProvider(photoUrl!) : null,
      child: photoUrl?.trim().isNotEmpty == true ? null : Text(initial, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -.1),
        ),
      );
}

class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context).withValues(alpha: .9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1)
                Divider(height: 1, indent: 58, color: AppColors.borderOf(context)),
            ],
          ],
        ),
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
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
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 21, color: AppColors.accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      );
}
