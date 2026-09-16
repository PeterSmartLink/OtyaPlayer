import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/audio_session_service.dart';
import '../../../core/services/media_notification_service.dart';
import '../../../shared/widgets/album_art_thumb.dart';
import 'audio_player_screen.dart';
import 'queue_screen.dart';

final miniPlayerItemProvider = StateProvider<MediaItem?>((_) => null);

final _miniIsPlayingProvider = Provider<bool>((ref) {
  return ref.watch(audioPlayerProvider.select((s) => s.isPlaying));
});

final _miniPositionProvider = Provider<Duration>((ref) {
  return ref.watch(audioPlayerProvider.select((s) => s.position));
});

final _miniDurationProvider = Provider<Duration>((ref) {
  return ref.watch(audioPlayerProvider.select((s) => s.duration));
});

/// Persistent Now Playing surface used across the app.
///
/// It follows playback across Video · Music · Me so changing tabs never kills
/// audio. Unlike the old implementation it also has an explicit close action:
/// closing means "stop showing/playing this item", not merely hide the card.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  MediaItem? _lastItem;
  double _dragOffset = 0;

  static const _dismissThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _openPlayer(MediaItem item) {
    HapticFeedback.selectionClick();
    context.push('/player/audio', extra: {'item': item, 'resumeOnly': true});
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    ref.read(audioPlayerProvider.notifier).pause();
    ref.read(queueProvider.notifier).clear();
    ref.read(miniPlayerItemProvider.notifier).state = null;
    unawaited(MediaNotificationService.instance.dismiss());
    unawaited(AudioSessionService.instance.deactivate());
    if (mounted) setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(miniPlayerItemProvider);

    if (item != null && _lastItem == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _slideCtrl.forward();
      });
    } else if (item == null && _lastItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _slideCtrl.reverse();
      });
    }
    _lastItem = item;

    if (item == null && !_slideCtrl.isAnimating) {
      return const SizedBox.shrink();
    }

    final displayItem = item ?? _lastItem;
    if (displayItem == null) return const SizedBox.shrink();

    return SlideTransition(
      position: _slideAnim,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.delta.dy <= 0) return;
          setState(() {
            _dragOffset = (_dragOffset + details.delta.dy)
                .clamp(0, _dismissThreshold * 1.5);
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset >= _dismissThreshold ||
              (details.primaryVelocity ?? 0) > 400) {
            _dismiss();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 300) return;
          HapticFeedback.mediumImpact();
          if (velocity < 0) {
            ref.read(audioPlayerProvider.notifier).skipNext();
          } else {
            ref.read(audioPlayerProvider.notifier).skipPrevious();
          }
        },
        onTap: () => _openPlayer(displayItem),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(0, _dragOffset, 0),
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 3),
          child: Opacity(
            opacity: (1 - _dragOffset / (_dismissThreshold * 1.5))
                .clamp(0.0, 1.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .22),
                        blurRadius: 18,
                        spreadRadius: -8,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(7),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AlbumArtThumb(
                                  albumArtPath: displayItem.albumArtPath,
                                  size: 50,
                                  borderRadius: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayItem.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      displayItem.artist ?? 'Unknown artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 10.8,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const _PlayPauseButton(),
                            IconButton(
                              tooltip: 'Close player',
                              visualDensity: VisualDensity.compact,
                              onPressed: _dismiss,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textSecondary,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 2),
                          ],
                        ),
                      ),
                      const _MiniSeekBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(_miniIsPlayingProvider);

    return Semantics(
      button: true,
      label: isPlaying ? 'Pause' : 'Play',
      child: InkResponse(
        radius: 24,
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(audioPlayerProvider.notifier).togglePlay();
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.accentGradientDiag,
            border: Border.all(
              color: Colors.white.withValues(alpha: .18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandViolet.withValues(alpha: .22),
                blurRadius: 14,
                spreadRadius: -3,
              ),
            ],
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _MiniSeekBar extends ConsumerStatefulWidget {
  const _MiniSeekBar();

  @override
  ConsumerState<_MiniSeekBar> createState() => _MiniSeekBarState();
}

class _MiniSeekBarState extends ConsumerState<_MiniSeekBar> {
  bool _isDragging = false;
  double _dragProgress = 0;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(_miniPositionProvider);
    final duration = ref.watch(_miniDurationProvider);
    final totalMs = duration.inMilliseconds;

    final progress = _isDragging
        ? _dragProgress
        : totalMs > 0
            ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;

    void updateFromDx(double dx, double width) {
      if (totalMs <= 0 || width <= 0) return;
      final fraction = (dx / width).clamp(0.0, 1.0);
      setState(() => _dragProgress = fraction);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (totalMs <= 0) return;
            final fraction =
                (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            ref.read(audioPlayerProvider.notifier).seek(
                  Duration(milliseconds: (fraction * totalMs).round()),
                );
          },
          onHorizontalDragStart: (details) {
            HapticFeedback.selectionClick();
            setState(() {
              _isDragging = true;
              _dragProgress = progress;
            });
            updateFromDx(details.localPosition.dx, constraints.maxWidth);
          },
          onHorizontalDragUpdate: (details) {
            updateFromDx(details.localPosition.dx, constraints.maxWidth);
          },
          onHorizontalDragEnd: (_) {
            if (totalMs > 0) {
              ref.read(audioPlayerProvider.notifier).seek(
                    Duration(milliseconds: (_dragProgress * totalMs).round()),
                  );
            }
            setState(() => _isDragging = false);
          },
          child: SizedBox(
            height: 8,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                height: _isDragging ? 4 : 3,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: _isDragging ? 4 : 3,
                  backgroundColor: Colors.white.withValues(alpha: .10),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
