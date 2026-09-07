from pathlib import Path

native_path = Path('android/app/src/main/kotlin/com/otyaplayer/app/MainActivity.kt')
flutter_path = Path('lib/features/video/presentation/widgets/video_tab_widgets.dart')

native = native_path.read_text()
flutter = flutter_path.read_text()

replacements = [
    (
        'val thumbDir = File(cacheDir, "video_thumbs").apply { mkdirs() }',
        'val thumbDir = File(cacheDir, "video_thumbs_v2").apply { mkdirs() }',
    ),
    ('Size(320, 180)', 'Size(720, 405)'),
    (
        'it.compress(Bitmap.CompressFormat.JPEG, 82, output)',
        'it.compress(Bitmap.CompressFormat.JPEG, 90, output)',
    ),
]

for old, new in replacements:
    if old not in native:
        raise SystemExit(f'native thumbnail source no longer matches expected pattern: {old}')
    native = native.replace(old, new, 1)

old_frame = '''                retriever.setDataSource(videoPath)
                bitmap = retriever.getFrameAtTime(
                    1_000_000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                ) ?: retriever.frameAtTime
'''
new_frame = '''                retriever.setDataSource(videoPath)
                val durationMs = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION,
                )?.toLongOrNull() ?: 0L
                // Avoid choosing a black/logo frame at the very beginning when
                // possible. Ten percent is representative for short/long local
                // clips, bounded so thumbnail generation stays predictable.
                val frameUs = if (durationMs > 0L) {
                    (durationMs * 100L).coerceIn(1_000_000L, 30_000_000L)
                } else {
                    1_000_000L
                }
                bitmap = retriever.getFrameAtTime(
                    frameUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                ) ?: retriever.frameAtTime
'''
if old_frame not in native:
    raise SystemExit('representative-frame source no longer matches expected block')
native = native.replace(old_frame, new_frame, 1)

old_render = '''                  cacheWidth: 480,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) => _placeholder(context),
'''
new_render = '''                  // Native v2 thumbnails are 720px wide. Decode near the
                  // source size and use balanced filtering so HD local media
                  // remains crisp without forcing full-resolution frames into
                  // scrolling-list memory.
                  cacheWidth: 720,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _placeholder(context),
'''
if old_render not in flutter:
    raise SystemExit('Flutter thumbnail renderer no longer matches expected block')
flutter = flutter.replace(old_render, new_render, 1)

native_path.write_text(native)
flutter_path.write_text(flutter)

print('Upgraded Otya video thumbnails: v2 cache, 720x405, JPEG 90, medium Flutter filtering.')
