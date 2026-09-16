import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../shared/widgets/album_art_thumb.dart';
import '../../../shared/widgets/permission_denied_screen.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../my_space/presentation/providers/my_space_provider.dart';
import '../../player/presentation/mini_player.dart';
import '../../player/presentation/queue_screen.dart';
import '../../search/smart_search_sheet.dart';

enum _MusicView { songs, albums, artists, folders, playlists }

final _musicViewProvider = StateProvider<_MusicView>((_) => _MusicView.songs);

class MusicTabScreen extends ConsumerStatefulWidget {
  const MusicTabScreen({super.key});

  @override
  ConsumerState<MusicTabScreen> createState() => _MusicTabScreenState();
}

class _MusicTabScreenState extends ConsumerState<MusicTabScreen>
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
    final view = ref.watch(_musicViewProvider);

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
            return _LibraryError(
              message: 'Otya could not refresh your music library.',
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

  Widget _content(BuildContext context, List<MediaItem> items, _MusicView view) {
    final songs = items.where((item) => !item.isVideo).toList(growable: false)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: _Header(songCount: songs.length)),
        SliverToBoxAdapter(child: _ViewPicker(value: view)),
        if (songs.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyMusic())
        else if (view == _MusicView.songs)
          _songs(songs)
        else if (view == _MusicView.albums)
          _groups(context, songs, groupBy: (item) => _cleanGroup(item.album, 'Unknown album'), icon: Icons.album_rounded, route: '/music/album')
        else if (view == _MusicView.artists)
          _groups(context, songs, groupBy: (item) => _cleanGroup(item.artist, 'Unknown artist'), icon: Icons.person_rounded, route: '/music/artist')
        else if (view == _MusicView.folders)
          _groups(context, songs, groupBy: _folderName, icon: Icons.folder_rounded, route: '/music/folder')
        else
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.queue_music_rounded, size: 54, color: AppColors.accent),
                    const SizedBox(height: 14),
                    const Text('Your playlists live in one place', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    const Text('Create, rename and manage local playlists without an account.', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => context.push('/playlists'),
                      icon: const Icon(Icons.queue_music_rounded),
                      label: const Text('Open Playlists'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  SliverList _songs(List<MediaItem> songs) => SliverList.builder(
        itemCount: songs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  final queue = List<MediaItem>.from(songs)..shuffle();
                  _play(context, queue, 0);
                },
                icon: const Icon(Icons.shuffle_rounded),
                label: Text('Shuffle ${songs.length} song${songs.length == 1 ? '' : 's'}'),
              ),
            );
          }
          final songIndex = index - 1;
          final item = songs[songIndex];
          return _SongTile(item: item, queue: songs, index: songIndex, onPlay: () => _play(context, songs, songIndex));
        },
      );

  SliverList _groups(
    BuildContext context,
    List<MediaItem> songs, {
    required String Function(MediaItem) groupBy,
    required IconData icon,
    required String route,
  }) {
    final map = <String, List<MediaItem>>{};
    for (final song in songs) {
      map.putIfAbsent(groupBy(song), () => <MediaItem>[]).add(song);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Icon(icon, color: AppColors.accent),
          ),
          title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${entry.value.length} song${entry.value.length == 1 ? '' : 's'}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(route, extra: {'name': entry.key, 'items': entry.value}),
        );
      },
    );
  }

  void _play(BuildContext context, List<MediaItem> queue, int index) {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    HapticFeedback.lightImpact();
    final item = queue[index];
    ref.read(queueProvider.notifier).setQueue(queue, startIndex: index);
    ref.read(miniPlayerItemProvider.notifier).state = item;
    context.push('/player/audio', extra: item);
  }

  static String _cleanGroup(String? value, String fallback) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty || clean == '<unknown>' ? fallback : clean;
  }

  static String _folderName(MediaItem item) {
    final segments = item.filePath.replaceAll('\\', '/').split('/');
    if (segments.length < 2) return 'Device';
    final name = segments[segments.length - 2].trim();
    return name.isEmpty ? 'Device' : name;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.songCount});
  final int songCount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Music', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.7)),
                  Text('$songCount local song${songCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Search your library',
              onPressed: () {
                HapticFeedback.selectionClick();
                SmartSearchSheet.show(context);
              },
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
      );
}

class _ViewPicker extends ConsumerWidget {
  const _ViewPicker({required this.value});
  final _MusicView value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      (_MusicView.songs, 'Songs'),
      (_MusicView.albums, 'Albums'),
      (_MusicView.artists, 'Artists'),
      (_MusicView.folders, 'Folders'),
      (_MusicView.playlists, 'Playlists'),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final option = options[index];
          return ChoiceChip(
            selected: option.$1 == value,
            label: Text(option.$2),
            onSelected: (_) {
              HapticFeedback.selectionClick();
              ref.read(_musicViewProvider.notifier).state = option.$1;
            },
          );
        },
      ),
    );
  }
}

class _SongTile extends ConsumerWidget {
  const _SongTile({required this.item, required this.queue, required this.index, required this.onPlay});
  final MediaItem item;
  final List<MediaItem> queue;
  final int index;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(miniPlayerItemProvider)?.id == item.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          AlbumArtThumb(albumArtPath: item.albumArtPath, size: 46, borderRadius: 12),
          if (active)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 17,
                height: 17,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.graphic_eq_rounded, size: 11, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? AppColors.accent : null)),
      subtitle: Text([
        if ((item.artist ?? '').trim().isNotEmpty && item.artist != '<unknown>') item.artist!.trim(),
        item.formattedDuration,
      ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: onPlay,
    );
  }
}

class _EmptyMusic extends StatelessWidget {
  const _EmptyMusic();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note_rounded, size: 58, color: AppColors.accent),
              const SizedBox(height: 14),
              const Text('No music found', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              const Text('Otya shows playable audio discovered by Android MediaStore. Check media permissions if songs are missing.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 50, color: AppColors.error),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
            ],
          ),
        ),
      );
}

class MusicFolderDetailPage extends _MusicGroupDetailPage {
  const MusicFolderDetailPage({super.key, required super.name, required super.items})
      : super(icon: Icons.folder_rounded);
}

class MusicAlbumDetailPage extends _MusicGroupDetailPage {
  const MusicAlbumDetailPage({super.key, required super.name, required super.items})
      : super(icon: Icons.album_rounded);
}

class MusicArtistDetailPage extends _MusicGroupDetailPage {
  const MusicArtistDetailPage({super.key, required super.name, required super.items})
      : super(icon: Icons.person_rounded);
}

class _MusicGroupDetailPage extends ConsumerWidget {
  const _MusicGroupDetailPage({
    super.key,
    required this.name,
    required this.items,
    required this.icon,
  });

  final String name;
  final List<MediaItem> items;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = List<MediaItem>.from(items)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    void play(int index) {
      if (songs.isEmpty || index < 0 || index >= songs.length) return;
      final item = songs[index];
      ref.read(queueProvider.notifier).setQueue(songs, startIndex: index);
      ref.read(miniPlayerItemProvider.notifier).state = item;
      context.push('/player/audio', extra: item);
    }

    return WallpaperScaffold(
      appBar: AppBar(title: Text(name)),
      body: songs.isEmpty
          ? const Center(child: Text('No songs found'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final item = songs[index];
                return ListTile(
                  leading: item.albumArtPath != null
                      ? AlbumArtThumb(
                          albumArtPath: item.albumArtPath,
                          size: 44,
                          borderRadius: 12,
                        )
                      : Icon(icon, color: AppColors.accent),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if ((item.artist ?? '').trim().isNotEmpty &&
                          item.artist != '<unknown>')
                        item.artist!.trim(),
                      item.formattedDuration,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () => play(index),
                );
              },
            ),
    );
  }
}
