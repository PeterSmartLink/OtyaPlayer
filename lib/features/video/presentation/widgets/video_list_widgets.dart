part of '../video_tab_screen.dart';

/// Phone-first video row used by the main library and folder detail pages.
///
/// A video is a visual item, but a two-column phone grid made thumbnails, names
/// and folder context too small. The preview is now a clean true-16:9 surface:
/// metadata stays beside it and Otya avoids covering the frame with a large
/// centre play badge that made even good thumbnails feel cramped or blurry.
class _VideoListCard extends StatelessWidget {
  const _VideoListCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = _resumeProgress(item);
    return Semantics(
      button: true,
      label: 'Play ${item.title}',
      child: Material(
        color: AppColors.cardOf(context).withValues(alpha: .90),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 148,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _VideoThumb(item: item, radius: 0),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0x4A000000),
                                ],
                                begin: Alignment.center,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 7,
                            top: 7,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.background.withValues(alpha: .54),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .42),
                                ),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: _DurationBadge(label: item.formattedDuration),
                          ),
                          if (progress > .02 && progress < .98)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.brandCyan,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            MediaNewIndicator(item: item),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(
                              Icons.folder_outlined,
                              size: 14,
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
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              item.formattedSize,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                            if (progress > .02 && progress < .98) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${(progress * 100).round()}% watched',
                                style: const TextStyle(
                                  color: AppColors.brandCyan,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const Spacer(),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ],
                    ),
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
