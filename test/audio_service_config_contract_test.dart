import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio service keeps foreground protection for background music', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('androidStopForegroundOnPause: false'));
    expect(source, contains('androidNotificationOngoing: true'));
    expect(
      source,
      contains(
        'androidNotificationOngoing: true,\n'
        '      androidStopForegroundOnPause: false',
      ),
    );
  });

  test('media session is registered before runApp can start playback', () {
    final source = File('lib/main.dart').readAsStringSync();

    final configure = source.indexOf(
      'AudioHandlerSingleton.instance.configureEnsureReady(_ensurePlaybackPlatform);',
    );
    final startup = source.indexOf(
      "await _safeBackground('playback platform', _ensurePlaybackPlatform);",
    );
    final runApp = source.indexOf('runApp(');

    expect(configure, greaterThanOrEqualTo(0));
    expect(startup, greaterThan(configure));
    expect(runApp, greaterThan(startup));
  });

  test('system UI configuration cannot block AudioService initialization', () {
    final source = File('lib/main.dart').readAsStringSync();

    final playbackStart = source.indexOf('Future<void> _initPlaybackPlatformOnce()');
    final systemUiStart = source.indexOf('Future<void> _configureSystemUi()');
    final playbackSection = source.substring(playbackStart, systemUiStart);

    expect(playbackStart, greaterThanOrEqualTo(0));
    expect(systemUiStart, greaterThan(playbackStart));
    expect(playbackSection, contains('AudioService.init('));
    expect(playbackSection, isNot(contains('SystemChrome.')));
    expect(source, contains("_safeBackground('system UI', _configureSystemUi)"));
  });
}
