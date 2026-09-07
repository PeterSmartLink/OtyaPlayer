import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/database/otya_database.dart';
import '../../../core/models/media_item.dart';
import '../../../shared/widgets/media_new_indicator.dart';
import '../../../shared/widgets/otya_logo.dart';
import '../../../shared/widgets/permission_denied_screen.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../my_space/presentation/providers/my_space_provider.dart';
import '../../player/presentation/queue_screen.dart';
import '../../search/smart_search_sheet.dart';

part 'widgets/video_tab_widgets.dart';
part 'widgets/video_list_widgets.dart';

enum _VideoView { videos, folders, playlists }

final _videoViewProvider = StateProvider<_VideoView>((_) => _VideoView.videos);

class VideoTabScreen extends ConsumerStatefulWidget {
  const VideoTabScreen({super.key});

  @override
  ConsumerState<VideoTabScreen> createState() => _VideoTabScreenState();
}

class _VideoTabScreenState extends ConsumerState<VideoTabScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(mediaLibraryProvider.notifier).backgroundRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final library = ref.watch(mediaLibraryProvider);
    final view = ref.watch(_videoViewProvider);
    return WallpaperScaffold(
      body: SafeArea(
        child: library.when(
          loading: () {
            final cached = library.valueOrNull;
            return cached == null
                ? const Center(child: CircularProgressIndicator())
                : _content(context, cached, view);
          },
          error: (error, _) {
            if (error.toString().toLowerCase().contains('permission')) {
              return PermissionDeniedScreen(
                onRetry: () => ref.read(mediaLibraryProvider.notifier).refresh(),
              );
            }
            return _VideoError(
              onRetry: () => ref.read(mediaLibraryProvider.notifier).refresh(),
            );
          },
          data: (items) => RefreshIndicator(
            onRefresh: () => ref.read(mediaLibraryProvider.notifier).refresh(),
            child: _content(context, items, view),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, List<MediaItem> items, _VideoView view) {
    final videos = items.where((item) => item.isVideo).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    final continueWatching = <MediaItem>[];
    for (final item in videos.take(80)) {
      final progress = _resumeProgress(item);
      if (progress > 0.02 && progress < 0.96) {
        continueWatching.add(item);
        if (continueWatching.length == 10) break;
      }
    }

    return CustomScrollView(
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: _VideoHeader(count: videos.length)),
        SliverToBoxAdapter(child: _VideoPicker(value: view)),
        if (videos.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyVideo())
        else if (view == _VideoView.videos) ...[
          if (continueWatching.isNotEmpty)
            SliverToBoxAdapter(
              child: _ContinueWatching(
                items: continueWatching,
                onPlay: (item) {
                  final index = videos.indexWhere((video) => video.id == item.id);
                  _playVideo(context, videos, index);
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'On this device',
              subtitle: 'Your videos, full-width and easy to scan',
              actionLabel: 'Shuffle',
              actionIcon: Icons.shuffle_rounded,
              onAction: () {
                final queue = List<MediaItem>.from(videos)..shuffle();
                _playVideo(context, queue, 0);
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
            sliver: SliverList.separated(
              itemCount: videos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _VideoListCard(
                item: videos[index],
                onTap: () => _playVideo(context, videos, index),
              ),
            ),
          ),
        ] else if (view == _VideoView.folders)
          _folderSliver(context, videos)
        else
          const SliverToBoxAdapter(child: _SharedPlaylistsCard()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _folderSliver(BuildContext context, List<MediaItem> videos) {
    final folders = <String, List<MediaItem>>{};
    for (final item in videos) {
      final folder = _folderName(item.filePath);
      folders.putIfAbsent(folder, () => <MediaItem>[]).add(item);
    }

    final entries = folders.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.crossAxisExtent >= 820
            ? 4
            : constraints.crossAxisExtent >= 560
                ? 3
                : 2;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = entries[index];
                return _FolderCard(
                  name: entry.key,
                  items: entry.value,
                  onTap: () => context.push(
                    '/video/folder',
                    extra: {'name': entry.key, 'items': entry.value},
                  ),
                );
              },
              childCount: entries.length,
            ),
          ),
        );
      },
    );
  }

  void _playVideo(BuildContext context, List<MediaItem> queue, int index) {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    HapticFeedback.lightImpact();
    ref.read(queueProvider.notifier).setQueue(queue, startIndex: index);
    context.push('/player/video', extra: queue[index]);
  }
}

class VideoFolderDetailPage extends ConsumerWidget {
  const VideoFolderDetailPage({
    super.key,
    required this.name,
    required this.items,
  });

  final String name;
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = items.where((item) => item.isVideo).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${videos.length} video${videos.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: videos.isEmpty
          ? const Center(child: Text('No videos are available in this folder.'))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                14,
                10,
                14,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              itemCount: videos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _VideoListCard(
                item: videos[index],
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref
                      .read(queueProvider.notifier)
                      .setQueue(videos, startIndex: index);
                  context.push('/player/video', extra: videos[index]);
                },
              ),
            ),
    );
  }
}
