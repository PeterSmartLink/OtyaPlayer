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
}
