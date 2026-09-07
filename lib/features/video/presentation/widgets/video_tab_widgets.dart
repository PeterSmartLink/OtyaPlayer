part of '../video_tab_screen.dart';

class _VideoHeader extends StatelessWidget {
  const _VideoHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        child: Row(
          children: [
            const OtyaMark(size: 38),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Video',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.5,
                    ),
                  ),
                  Text(
                    '$count local video${count == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Search OTYA',
              onPressed: () {
                HapticFeedback.selectionClick();
                SmartSearchSheet.show(context);
              },
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'Watch history',
              onPressed: () => context.push('/history'),
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        ),
      );
}

class _VideoPicker extends ConsumerWidget {
  const _VideoPicker({required this.value});

  final _VideoView value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      (_VideoView.videos, Icons.video_library_rounded, 'Videos'),
      (_VideoView.folders, Icons.folder_rounded, 'Folders'),
      (_VideoView.playlists, Icons.playlist_play_rounded, 'Playlists'),
    ];

    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ChoiceChip(
            selected: option.$1 == value,
            avatar: Icon(option.$2, size: 17),
            label: Text(option.$3),
            onSelected: (_) {
              HapticFeedback.selectionClick();
              ref.read(_videoViewProvider.notifier).state = option.$1;
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.play_arrow_rounded, size: 17),
                label: Text(actionLabel!),
              ),
          ],
        ),
      );
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.items, required this.onPlay});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onPlay;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Continue watching',
            subtitle: 'Pick up from where you stopped',
          ),
          SizedBox(
            height: 166,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return _ResumeCard(item: item, onTap: () => onPlay(item));
              },
            ),
          ),
        ],
      );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = _resumeProgress(item);
    return SizedBox(
      width: 220,
      child: Material(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _VideoThumb(item: item, radius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Color(0xB3000000)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    const Center(
                      child: _PlayBadge(size: 44),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = _resumeProgress(item);
    return Semantics(
      button: true,
      label: 'Play ${item.title}',
      child: Material(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _VideoThumb(item: item, radius: 0),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Color(0x8F000000)],
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    const Center(child: _PlayBadge(size: 42)),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _DurationBadge(label: item.formattedDuration),
                    ),
                    if (progress > 0.02 && progress < 0.98)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        MediaNewIndicator(item: item),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _folderName(item.filePath),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.formattedSize,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.name,
    required this.items,
    required this.onTap,
  });

  final String name;
  final List<MediaItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = items.isEmpty ? null : items.first;
    return Semantics(
      button: true,
      label: '$name folder, ${items.length} videos',
      child: Material(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                _VideoThumb(item: preview, radius: 0)
              else
                Container(color: AppColors.cardOf(context)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x22000000), Color(0xE6080B12)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: .35),
                        ),
                      ),
                      child: const Icon(
                        Icons.folder_rounded,
                        color: AppColors.accent,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${items.length} video${items.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedPlaylistsCard extends StatelessWidget {
  const _SharedPlaylistsCard();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        child: Material(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/playlists');
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradientDiag,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.playlist_play_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your playlists',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'OTYA playlists can contain both video and audio. Manage them in one place.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .48),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70),
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 27,
        ),
      );
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.item, this.radius = 14});

  final MediaItem item;
  final double radius;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  static const _channel = MethodChannel('com.otyaplayer.app/media_store');
  static final Map<String, String?> _cache = <String, String?>{};
  static const int _maxCacheEntries = 320;

  String? _path;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _path = widget.item.thumbnailPath ?? _cache[widget.item.id];
    if (_path == null) _load();
  }

  @override
  void didUpdateWidget(covariant _VideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id == widget.item.id) return;
    _path = widget.item.thumbnailPath ?? _cache[widget.item.id];
    if (_path == null) _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final itemId = widget.item.id;
    try {
      final path = await _channel.invokeMethod<String>('getVideoThumbnail', {
        'path': widget.item.filePath,
        'id': widget.item.mediaStoreId ?? '',
      }).timeout(const Duration(seconds: 5));
      if (generation != _loadGeneration || itemId != widget.item.id) return;
      _cache[itemId] = path;
      if (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      if (mounted) setState(() => _path = path);
    } catch (_) {
      if (generation != _loadGeneration || itemId != widget.item.id) return;
      _cache[itemId] = null;
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: ColoredBox(
          color: AppColors.cardOf(context),
          child: _path != null && _path!.isNotEmpty
              ? Image.file(
                  File(_path!),
                  fit: BoxFit.cover,
                  // Native v2 thumbnails are 720px wide. Decode near the
                  // source size and use balanced filtering so HD local media
                  // remains crisp without forcing full-resolution frames into
                  // scrolling-list memory.
                  cacheWidth: 720,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _placeholder(context),
                )
              : _placeholder(context),
        ),
      );

  Widget _placeholder(BuildContext context) => Container(
        color: AppColors.cardOf(context),
        alignment: Alignment.center,
        child: const Icon(
          Icons.movie_creation_outlined,
          color: AppColors.accent,
          size: 34,
        ),
      );
}

class _EmptyVideo extends StatelessWidget {
  const _EmptyVideo();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_outlined, size: 58, color: AppColors.accent),
              SizedBox(height: 14),
              Text(
                'No videos found',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 7),
              Text(
                'OTYA shows playable video discovered by Android MediaStore. Check media permissions if videos are missing.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 50,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'OTYA could not refresh your video library.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}

int _gridColumns(double width) {
  if (width >= 1100) return 5;
  if (width >= 800) return 4;
  if (width >= 540) return 3;
  return 2;
}

String _folderName(String path) {
  final normalized = path.replaceAll('\\', '/').split('/');
  if (normalized.length < 2) return 'Device';
  final folder = normalized[normalized.length - 2].trim();
  return folder.isEmpty ? 'Device' : folder;
}

double _resumeProgress(MediaItem item) {
  final duration = item.duration;
  if (duration == null || duration.inMilliseconds <= 0) return 0;
  final position = OtyaDatabase.instance.getSeekPosition(item.id);
  if (position == null || position <= const Duration(seconds: 5)) return 0;
  return (position.inMilliseconds / duration.inMilliseconds)
      .clamp(0.0, 1.0)
      .toDouble();
}
