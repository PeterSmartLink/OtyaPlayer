import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void expectNotContains(String source, String needle) {
  expect(source.contains(needle), isFalse);
}

void main() {
  test('Now Playing metadata is queued until the audio handler is ready', () {
    final handler = File('lib/core/services/audio_handler.dart').readAsStringSync();
    final notifications = File('lib/core/services/media_notification_service.dart')
        .readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(handler, contains('MediaItem? _pendingMediaItem'));
    expect(handler, contains('bool? _pendingPlaying'));
    expect(handler, contains('Queued Now Playing metadata'));
    expect(notifications, contains('AudioHandlerSingleton.instance.setMediaItem'));
    expect(notifications, contains('AudioHandlerSingleton.instance.setPlaying'));
    expectNotContains(handler, "album: 'OTYA Player'");
    expect(main, contains("androidNotificationChannelName: 'Otya — Now Playing'"));
    expect(main, contains('notificationColor: AppColors.brandBlue'));
    expectNotContains(main, 'notificationColor: const Color(0xFF2979FF)');
  });

  test('crash reporting is installed once before the first frame', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, contains('await CrashReporter.instance.init();'));
    expectNotContains(main, "_safeBackground('crash reporter'");
    expectNotContains(main, 'FlutterError.onError = (details)');
    expectNotContains(main, 'PlatformDispatcher.instance.onError =');
  });

  test('crash reporting suppresses duplicate telemetry storms', () {
    final reporter =
        File('lib/core/services/crash_reporter.dart').readAsStringSync();

    expect(reporter, contains('_duplicateWindow'));
    expect(reporter, contains('_maxReportsPerSession'));
    expect(reporter, contains('_recentFingerprints'));
    expect(reporter, contains('_uploadsInFlight'));
    expect(reporter, contains('Suppressed duplicate'));
    expect(reporter, contains('if (!_uploadsInFlight.add(uploadKey)) return;'));
  });

  test('update checks do not pretend disabled or failed checks mean current', () {
    final updates = File('lib/core/services/update_service.dart').readAsStringSync();

    expect(updates, contains('if (!Environment.selfUpdateEnabled) {'));
    expect(updates, contains('Updates for this build are managed by Google Play.'));
    expect(updates, contains('UpdateCheckState.unavailable'));
    expect(updates, contains('UpdateCheckState.current'));
    expect(updates, contains('UpdateCheckState.updateAvailable'));
  });

  test('direct self-update accepts only the immutable tagged APK authority', () {
    final updates = File('lib/core/services/update_service.dart').readAsStringSync();

    expect(updates, contains("'exactArm64' : 'exactArm32'"));
    expect(updates, contains('_officialExactApk('));
    expect(updates, contains("uri.path != '/apk/\$abi'"));
    expect(updates, contains('tagValues.single != tag'));
    expectNotContains(updates, 'aliasKey');
    expectNotContains(updates, 'downloads[exactKey] ??');
  });

  test('media refreshes share one in-flight scan without orphaned errors', () {
    final repository =
        File('lib/features/my_space/data/media_repository.dart').readAsStringSync();

    expect(repository, contains('Future<List<MediaItem>>? _scanInFlight'));
    expect(repository, contains('final existingScan = _scanInFlight'));
    expect(repository, contains('if (existingScan != null) return existingScan;'));
    expect(repository, contains('if (identical(_scanInFlight, scan))'));
    expectNotContains(repository, 'Completer<List<MediaItem>>');
    expectNotContains(repository, 'completeError(e)');
  });

  test('video retry releases failed native player before replacement', () {
    final engine =
        File('lib/core/services/media_kit_engine.dart').readAsStringSync();

    expect(engine, contains('final generation = ++_playerGeneration'));
    expect(engine, contains('Future<void> _releaseCurrentPlayer()'));
    expect(engine, contains('await _releaseCurrentPlayer();'));
    expect(engine, contains('await player.dispose();'));
    expect(engine, contains('onPressed: _retrying ? null : _retryPlayer'));
    expectNotContains(
      engine,
      'onPressed: () {\n                      setState(() { _hasError = false;',
    );
  });

  test('audio load failures expose retry state immediately', () {
    final audio = File(
      'lib/features/player/presentation/audio_player_screen.dart',
    ).readAsStringSync();

    expect(audio, contains('final bool hasLoadError;'));
    expect(audio, contains('hasLoadError: true'));
    expect(audio, contains('hasLoadError: false'));
    expect(
      audio,
      contains('final showRetry = _showRetry || playerState.hasLoadError;'),
    );
  });

  test('hot UI paths avoid synchronous filesystem existence checks', () {
    const paths = [
      'lib/core/services/custom_theme_manager.dart',
      'lib/features/my_space/presentation/widgets/media_card.dart',
      'lib/features/downloads/presentation/downloads_screen.dart',
      'lib/features/video/presentation/video_tab_screen.dart',
      'lib/features/video/presentation/widgets/video_tab_widgets.dart',
      'lib/features/settings/presentation/theme_selection_screen.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expectNotContains(source, 'existsSync()');
    }
  });

  test('network timeout policy is not shortened by a nested wrapper', () {
    final client =
        File('lib/core/services/http_client.dart').readAsStringSync();

    expect(client, contains('.timeout(timeout)'));
    expectNotContains(client, 'request().timeout(_connectTimeout)');
    expectNotContains(client, 'static const Duration _connectTimeout');
  });

  test('startup fallback never uses widget state after disposal', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    final fallback = app.indexOf(
      'ref.read(settingsProvider.notifier).hydrate(const AppSettings());',
    );
    final mountedGuard = app.lastIndexOf('if (!mounted) return;', fallback);

    expect(fallback, greaterThanOrEqualTo(0));
    expect(mountedGuard, greaterThanOrEqualTo(0));
    expect(mountedGuard, lessThan(fallback));
  });
}
