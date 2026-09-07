part of '../audio_player_screen.dart';

class _AudioPlayerNowPlayingView extends StatelessWidget {
  final MediaItem activeItem;
  final AudioPlayerState playerState;
  final bool isShuffle;
  final bool showRetry;
  final double artPadding;
  final double playButtonSize;
  final double skipIconSize;
  final double spacing;
  final String speedLabel;
  final VoidCallback onBack;
  final VoidCallback onSleepExpire;
  final VoidCallback onOptions;
  final VoidCallback onSwipeNext;
  final VoidCallback onSwipePrevious;
  final VoidCallback onFavorite;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onShuffle;
  final VoidCallback onSpeed;
  final VoidCallback onRepeat;
  final VoidCallback onPrevious;
  final VoidCallback onSkipBack;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipForward;
  final VoidCallback onNext;
  final VoidCallback onLyrics;
  final VoidCallback onEqualizer;
  final VoidCallback onQueue;
  final VoidCallback onShare;

  const _AudioPlayerNowPlayingView({
    required this.activeItem,
    required this.playerState,
    required this.isShuffle,
    required this.showRetry,
    required this.artPadding,
    required this.playButtonSize,
    required this.skipIconSize,
    required this.spacing,
    required this.speedLabel,
    required this.onBack,
    required this.onSleepExpire,
    required this.onOptions,
    required this.onSwipeNext,
    required this.onSwipePrevious,
    required this.onFavorite,
    required this.onSeek,
    required this.onShuffle,
    required this.onSpeed,
    required this.onRepeat,
    required this.onPrevious,
    required this.onSkipBack,
    required this.onPlayPause,
    required this.onSkipForward,
    required this.onNext,
    required this.onLyrics,
    required this.onEqualizer,
    required this.onQueue,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return WallpaperScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 30,
                    ),
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  const Column(
                    children: [
                      Text(
                        'OTYA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppColors.brandCyan,
                          letterSpacing: 2.0,
                          fontFamily: 'Inter',
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'NOW PLAYING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.35,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SleepTimerButton(onExpire: onSleepExpire),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'More options',
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                    onPressed: onOptions,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: artPadding,
                  vertical: 5,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandBlue.withValues(alpha: .25),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: AppColors.brandCyan.withValues(alpha: .12),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: _AlbumArt(
                      albumArtPath: activeItem.albumArtPath,
                      isPlaying: playerState.isPlaying,
                      title: activeItem.title,
                      onSwipeLeft: onSwipeNext,
                      onSwipeRight: onSwipePrevious,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: spacing),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.surfaceElevated.withValues(alpha: .96),
                    AppColors.surface.withValues(alpha: .90),
                    AppColors.brandDeepBlue.withValues(alpha: .12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.brandCyan.withValues(alpha: .18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: .10),
                    blurRadius: 20,
                    spreadRadius: -7,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeItem.title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontFamily: 'Inter',
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              activeItem.artist ?? 'Unknown Artist',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                fontFamily: 'Inter',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: playerState.isFavorite
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        onPressed: onFavorite,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            playerState.isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key: ValueKey(playerState.isFavorite),
                            color: playerState.isFavorite
                                ? AppColors.brandRed
                                : AppColors.textSecondary,
                            size: 27,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SeekBar(
                    position: playerState.position,
                    duration: playerState.duration,
                    onSeek: onSeek,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing / 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ToggleIconBtn(
                    icon: Icons.shuffle_rounded,
                    active: isShuffle,
                    onTap: onShuffle,
                  ),
                  GestureDetector(
                    onTap: onSpeed,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated.withValues(alpha: .90),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: AppColors.brandCyan.withValues(alpha: .16),
                        ),
                      ),
                      child: Text(
                        speedLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandCyan,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                  _RepeatBtn(
                    repeat: playerState.repeat,
                    onTap: onRepeat,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing / 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous',
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: skipIconSize,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onPrevious();
                    },
                  ),
                  IconButton(
                    tooltip: 'Back 10 seconds',
                    icon: Icon(
                      Icons.replay_10_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: skipIconSize,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onSkipBack();
                    },
                  ),
                  GestureDetector(
                    onTap: onPlayPause,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: playButtonSize,
                      height: playButtonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.accentGradientDiag,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .22),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: .34),
                            blurRadius: 24,
                            spreadRadius: 1,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: AppColors.brandCyan.withValues(alpha: .18),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: playerState.isLoading && !showRetry
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : showRetry
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                )
                              : Icon(
                                  playerState.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Forward 10 seconds',
                    icon: Icon(
                      Icons.forward_10_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: skipIconSize,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onSkipForward();
                    },
                  ),
                  IconButton(
                    tooltip: 'Next',
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: skipIconSize,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onNext();
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SecondaryBtn(
                      icon: Icons.lyrics_rounded,
                      label: 'Lyrics',
                      onTap: onLyrics,
                    ),
                    _SecondaryBtn(
                      icon: Icons.graphic_eq_rounded,
                      label: 'Equalizer',
                      onTap: onEqualizer,
                    ),
                    _SecondaryBtn(
                      icon: Icons.queue_music_rounded,
                      label: 'Up Next',
                      onTap: onQueue,
                    ),
                    _SecondaryBtn(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      onTap: onShare,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
