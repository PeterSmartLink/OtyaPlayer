import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android generates a fresh high-quality thumbnail cache', () {
    final native = File(
      'android/app/src/main/kotlin/com/otyaplayer/app/MainActivity.kt',
    ).readAsStringSync();

    expect(native, contains('video_thumbs_v2'));
    expect(native, contains('Size(720, 405)'));
    expect(native, contains('Bitmap.CompressFormat.JPEG, 90'));
    expect(native, contains('MediaMetadataRetriever.METADATA_KEY_DURATION'));
    expect(native, contains('30_000_000L'));
    expect(native, isNot(contains('Size(320, 180)')));
    expect(native, isNot(contains('Bitmap.CompressFormat.JPEG, 82')));
  });

  test('Flutter does not soften upgraded video thumbnails', () {
    final widgets = File(
      'lib/features/video/presentation/widgets/video_tab_widgets.dart',
    ).readAsStringSync();

    expect(widgets, contains('cacheWidth: 720'));
    expect(widgets, contains('filterQuality: FilterQuality.medium'));
    expect(widgets, contains('gaplessPlayback: true'));
    expect(widgets, isNot(contains('filterQuality: FilterQuality.low')));
  });

  test('phone video rows use a clean single 16 by 9 preview', () {
    final row = File(
      'lib/features/video/presentation/widgets/video_list_widgets.dart',
    ).readAsStringSync();

    expect(row, contains('aspectRatio: 16 / 9'));
    expect(row, contains('width: 148'));
    expect(row, isNot(contains('width: 132')));
    expect(row, isNot(contains('width: 36,\n                            height: 36')));
  });
}
