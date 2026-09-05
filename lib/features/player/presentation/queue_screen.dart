import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/database/otya_database.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/new_media_tracker.dart';
import '../../../core/services/smart_shuffle_service.dart';
import '../../../shared/widgets/album_art_thumb.dart';

class QueueState {
  final List<MediaItem> items;
  final int currentIndex;
  final bool shuffle;
  const QueueState({
    this.items = const [],
    this.currentIndex = 0,
    this.shuffle = false,
  });

  QueueState copyWith({
    List<MediaItem>? items,
    int? currentIndex,
    bool? shuffle,
  }) => QueueState(
        items: items ?? this.items,
        currentIndex: currentIndex ?? this.currentIndex,
        shuffle: shuffle ?? this.shuffle,
      );

  MediaItem? get current =>
      items.isEmpty ? null : items[currentIndex.clamp(0, items.length - 1)];
}

class QueueNotifier extends StateNotifier<QueueState> {
  QueueNotifier() : super(const QueueState());

  void setQueue(List<MediaItem> items, {int startIndex = 0}) {
    final index = items.isEmpty ? 0 : startIndex.clamp(0, items.length - 1);
    state = state.copyWith(items: items, currentIndex: index);
    _recordCurrent();
  }

  void addToQueue(MediaItem item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.items.length) return;

    final currentId = state.current?.id;
    final updated = List<MediaItem>.from(state.items)..removeAt(index);
    if (updated.isEmpty) {
      state = const QueueState();
      return;
    }

    // Removing an item before the active item shifts its numeric index. Resolve
    // the active item by identity so playback does not silently jump tracks.
    final preservedIndex = currentId == null
        ? -1
        : updated.indexWhere((item) => item.id == currentId);
    final nextIndex = preservedIndex >= 0
        ? preservedIndex
        : index.clamp(0, updated.length - 1);

    state = state.copyWith(items: updated, currentIndex: nextIndex);
  }

  void reorder(int oldIndex, int newIndex) {
    final updated = List<MediaItem>.from(state.items);
    final currentId = state.current?.id;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    final currentIndex = currentId == null
        ? state.currentIndex
        : updated.indexWhere((entry) => entry.id == currentId);
    state = state.copyWith(
      items: updated,
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
    );
  }

  void next() {
    if (state.items.isEmpty) return;
    final int nextIndex;
    if (state.shuffle) {
      final history = OtyaDatabase.instance.getRecentlyPlayed(limit: 9999);
      final statsMap = <String, TrackStats>{
        for (final item in history)
          item.id: TrackStats(
            playCount: 1,
            lastPlayedMs: item.lastPlayedAt?.millisecondsSinceEpoch ?? 0,
            rating: 0,
            skipCount: 0,
          ),
      };
      final ids = state.items.map((i) => i.id).toList();
      final shuffled = SmartShuffleService.instance.smartShuffle(ids, statsMap);
      final currentId = state.items[state.currentIndex].id;
      final nextId = shuffled.firstWhere(
        (id) => id != currentId,
        orElse: () => shuffled.first,
      );
      nextIndex = state.items.indexWhere((item) => item.id == nextId);
    } else {
      nextIndex = (state.currentIndex + 1) % state.items.length;
    }
    state = state.copyWith(currentIndex: nextIndex < 0 ? 0 : nextIndex);
    _recordCurrent();
  }

  void previous() {
    if (state.items.isEmpty) return;
    final prev =
        (state.currentIndex - 1 + state.items.length) % state.items.length;
    state = state.copyWith(currentIndex: prev);
    _recordCurrent();
  }

  /// Restores an already-known queue position without recording a new play.
  /// This is used when a navigation attempt fails after the queue index moved.
  void restoreCurrentIndex(int index) {
    if (state.items.isEmpty) return;
    state = state.copyWith(
      currentIndex: index.clamp(0, state.items.length - 1),
    );
  }

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);

  void clear() => state = const QueueState();

  void _recordCurrent() {
    final item = state.current;
    if (item == null) return;
    NewMediaTracker.instance.markSeen(item).ignore();
    OtyaDatabase.instance.recordPlay(item).ignore();
  }
}

final queueProvider =
    StateNotifierProvider<QueueNotifier, QueueState>((_) => QueueNotifier());

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.width > 600
        ? MediaQuery.of(context).size.height * 0.64
        : MediaQuery.of(context).size.height * 0.82;
    const radius = BorderRadius.vertical(top: Radius.circular(30));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.92),
            borderRadius: radius,
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UP NEXT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.8,
                              color: AppColors.accent,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            queue.items.isEmpty
                                ? 'Nothing queued'
                                : '${queue.items.length} ${queue.items.length == 1 ? 'track' : 'tracks'} in queue',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                              fontFamily: 'Inter',
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _HeaderAction(
                      icon: Icons.shuffle_rounded,
                      active: queue.shuffle,
                      tooltip: 'Shuffle',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(queueProvider.notifier).toggleShuffle();
                      },
                    ),
                    const SizedBox(width: 8),
                    _HeaderAction(
                      icon: Icons.delete_sweep_outlined,
                      tooltip: 'Clear queue',
                      onTap: queue.items.isEmpty
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              ref.read(queueProvider.notifier).clear();
                            },
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.borderOf(context)),
              Expanded(
                child: queue.items.isEmpty
                    ? _EmptyQueue(colorScheme: cs)
                    : ReorderableListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          10,
                          12,
                          MediaQuery.of(context).padding.bottom + 24,
                        ),
                        itemCount: queue.items.length,
                        onReorder: (oldIndex, newIndex) {
                          HapticFeedback.mediumImpact();
                          final adjusted =
                              newIndex > oldIndex ? newIndex - 1 : newIndex;
                          ref
                              .read(queueProvider.notifier)
                              .reorder(oldIndex, adjusted);
                        },
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          elevation: 0,
                          child: ScaleTransition(
                            scale: Tween(begin: 1.0, end: 1.02)
                                .animate(animation),
                            child: child,
                          ),
                        ),
                        itemBuilder: (context, i) {
                          final item = queue.items[i];
                          final isCurrent = i == queue.currentIndex;
                          return Container(
                            key: ValueKey('${item.id}-$i'),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.accent.withValues(alpha: 0.085)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.accent.withValues(alpha: 0.24)
                                    : Colors.transparent,
                              ),
                            ),
                            child: ListTile(
                              minTileHeight: 66,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              leading: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: AlbumArtThumb(
                                      albumArtPath: item.albumArtPath,
                                      size: 48,
                                      borderRadius: 12,
                                    ),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      width: 19,
                                      height: 19,
                                      decoration: const BoxDecoration(
                                        color: AppColors.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.graphic_eq_rounded,
                                        color: Colors.white,
                                        size: 12,
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: cs.onSurface,
                                  fontFamily: 'Inter',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  item.artist ?? item.formattedDuration,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        cs.onSurface.withValues(alpha: 0.50),
                                    fontFamily: 'Inter',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCurrent)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 10),
                                      child: Text(
                                        'PLAYING',
                                        style: TextStyle(
                                          fontSize: 8,
                                          letterSpacing: 1.1,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.accent,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'Remove',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.42),
                                      size: 19,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(queueProvider.notifier)
                                          .removeAt(i);
                                    },
                                  ),
                                  Icon(
                                    Icons.drag_handle_rounded,
                                    color: cs.onSurface.withValues(alpha: 0.28),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
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

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final String tooltip;

  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.13)
                : cs.onSurface.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.25)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Icon(
            icon,
            color: active
                ? AppColors.accent
                : cs.onSurface
                    .withValues(alpha: onTap == null ? 0.22 : 0.58),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  final ColorScheme colorScheme;
  const _EmptyQueue({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.16),
                ),
              ),
              child: const Icon(
                Icons.queue_music_rounded,
                color: AppColors.accent,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Your queue is empty',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Choose music or video from your library and OTYA will build the queue here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.50),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
