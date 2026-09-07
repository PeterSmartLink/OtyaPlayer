import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File(
    'lib/features/video/presentation/video_tab_screen.dart',
  ).readAsStringSync();
  final widgets = File(
    'lib/features/video/presentation/widgets/video_tab_widgets.dart',
  ).readAsStringSync();
  final listWidgets = File(
    'lib/features/video/presentation/widgets/video_list_widgets.dart',
  ).readAsStringSync();

  test('video tab screen remains the lifecycle, refresh and queue owner', () {
    expect(screen, contains('with WidgetsBindingObserver'));
    expect(screen, contains('backgroundRefresh()'));
    expect(screen, contains('mediaLibraryProvider.notifier).refresh()'));
    expect(screen, contains('queueProvider.notifier).setQueue('));
    expect(screen, contains("context.push('/player/video'"));
    expect(screen, contains('class VideoFolderDetailPage'));

    expect(widgets, isNot(contains('WidgetsBindingObserver')));
    expect(widgets, isNot(contains('backgroundRefresh()')));
    expect(widgets, isNot(contains('queueProvider.notifier).setQueue(')));
    expect(widgets, isNot(contains('class VideoTabScreen')));
    expect(widgets, isNot(contains('class VideoFolderDetailPage')));
  });

  test('video tab presentation and artwork live in extracted parts', () {
    expect(screen, contains("part 'widgets/video_tab_widgets.dart';"));
    expect(screen, contains("part 'widgets/video_list_widgets.dart';"));
    expect(screen, contains('_VideoHeader('));
    expect(screen, contains('_VideoListCard('));
    expect(screen, contains('_FolderCard('));

    expect(widgets, contains("part of '../video_tab_screen.dart';"));
    expect(widgets, contains('class _VideoHeader'));
    expect(widgets, contains('class _FolderCard'));
    expect(widgets, contains('class _VideoThumb'));
    expect(widgets, contains("invokeMethod<String>('getVideoThumbnail'"));
    expect(widgets, isNot(contains('existsSync()')));

    expect(listWidgets, contains("part of '../video_tab_screen.dart';"));
    expect(listWidgets, contains('class _VideoListCard'));
    expect(listWidgets, contains('_VideoThumb(item: item'));
  });
}
