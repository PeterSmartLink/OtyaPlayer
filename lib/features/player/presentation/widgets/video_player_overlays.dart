import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/duration_formatter.dart';

class VideoPlayerControlsOverlay extends StatelessWidget {
  final String title;
  final bool ccEnabled;
  final bool isMuted;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double playbackSpeed;
  final String aspectRatioLabel;
  final VoidCallback onBack;
  final VoidCallback onToggleSubtitles;
  final VoidCallback onAudioTracks;
  final VoidCallback onEqualizer;
  final VoidCallback onMoreOptions;
  final VoidCallback onTogether;
  final VoidCallback onToggleMute;
  final VoidCallback onLock;
  final VoidCallback onRotate;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onRewind;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onForward;
  final VoidCallback onSpeed;
  final VoidCallback onAspectRatio;
  final VoidCallback onPip;

  const VideoPlayerControlsOverlay({
    super.key,
    required this.title,
    required this.ccEnabled,
    required this.isMuted,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.playbackSpeed,
    required this.aspectRatioLabel,
    required this.onBack,
    required this.onToggleSubtitles,
    required this.onAudioTracks,
    required this.onEqualizer,
    required this.onMoreOptions,
    required this.onTogether,
    required this.onToggleMute,
    required this.onLock,
    required this.onRotate,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onRewind,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onForward,
    required this.onSpeed,
    required this.onAspectRatio,
    required this.onPip,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xCC000000), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onBack();
                      },
                    ),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.closed_caption_rounded,
                        color: ccEnabled ? AppColors.accent : Colors.white70,
                        size: 20,
                      ),
                      tooltip: ccEnabled
                          ? 'Turn subtitles off'
                          : 'Turn subtitles on',
                      onPressed: onToggleSubtitles,
                    ),
                    IconButton(
                      tooltip: 'Audio tracks',
                      icon: const Icon(
                        Icons.audiotrack_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onAudioTracks();
                      },
                    ),
                    IconButton(
                      tooltip: 'Equalizer',
                      icon: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onEqualizer();
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onMoreOptions();
                      },
                      tooltip: 'More options',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isMuted ? 'Unmute' : 'Mute',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onToggleMute();
                    },
                    icon: Icon(
                      isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white70,
                      size: 23,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lock controls',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onLock();
                    },
                    icon: const Icon(
                      Icons.lock_open_rounded,
                      color: Colors.white70,
                      size: 23,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: IconButton(
                tooltip: 'Rotate screen',
                onPressed: onRotate,
                icon: const Icon(
                  Icons.screen_rotation_rounded,
                  color: Colors.white70,
                  size: 23,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xB8000000)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          DurationFormatter.format(position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'Inter',
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              activeTrackColor: AppColors.accent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: AppColors.accent,
                              overlayColor:
                                  AppColors.accent.withValues(alpha: 0.2),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                            ),
                            child: Slider(
                              value: position.inSeconds.toDouble().clamp(
                                    0,
                                    duration.inSeconds
                                        .toDouble()
                                        .clamp(1, double.infinity),
                                  ),
                              max: duration.inSeconds
                                  .toDouble()
                                  .clamp(1, double.infinity),
                              onChangeStart: onSeekStart,
                              onChanged: onSeekChanged,
                              onChangeEnd: onSeekEnd,
                            ),
                          ),
                        ),
                        Text(
                          DurationFormatter.format(duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          tooltip: 'Back 10 seconds',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onRewind();
                          },
                          icon: const Icon(
                            Icons.replay_10_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Previous',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onPrevious();
                          },
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.accent.withValues(alpha: 0.24),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: IconButton(
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              onPlayPause();
                            },
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Next',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onNext();
                          },
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Forward 10 seconds',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onForward();
                          },
                          icon: const Icon(
                            Icons.forward_10_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        TextButton(
                          onPressed: onSpeed,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '${playbackSpeed}x',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            onTogether();
                          },
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            backgroundColor: Colors.black.withValues(alpha: 0.24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.group_outlined, size: 18),
                          label: const Text('Together'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: aspectRatioLabel,
                          onPressed: onAspectRatio,
                          icon: const Icon(
                            Icons.aspect_ratio_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Picture in picture',
                          onPressed: onPip,
                          icon: const Icon(
                            Icons.picture_in_picture_alt_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class VideoPlayerLockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;

  const VideoPlayerLockOverlay({super.key, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Center(
        child: Semantics(
          button: true,
          label: 'Unlock video controls',
          child: InkWell(
            borderRadius: BorderRadius.circular(48),
            onTap: () {
              HapticFeedback.selectionClick();
              onUnlock();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 68,
                    minHeight: 68,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.32),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: AppColors.accent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tap to unlock',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VideoInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const VideoInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class VideoAudioTrackSheet extends StatelessWidget {
  final List<AudioTrack> tracks;
  final AudioTrack activeTrack;
  final void Function(AudioTrack) onSelect;

  const VideoAudioTrackSheet({
    super.key,
    required this.tracks,
    required this.activeTrack,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Audio Track',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 12),
          ...tracks.map((track) {
            final active = track.id == activeTrack.id;
            final label = track.language?.isNotEmpty == true
                ? track.language!
                : track.title?.isNotEmpty == true
                    ? track.title!
                    : 'Track ${tracks.indexOf(track) + 1}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: active ? AppColors.accent : AppColors.textSecondary,
                size: 20,
              ),
              title: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  color: active ? AppColors.accent : AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                onSelect(track);
              },
            );
          }),
        ],
      ),
    );
  }
}
