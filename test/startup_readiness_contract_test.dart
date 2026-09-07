import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('post-frame services run together after playback initialization', () {
    final source = File('lib/main.dart').readAsStringSync();

    final playback = source.indexOf(
      "await _safeBackground('playback platform', _ensurePlaybackPlatform);",
    );
    final notifications = source.indexOf('final notificationsReady =');
    final storage = source.indexOf('final storageReady =');
    final connectivity = source.indexOf('final connectivityReady =');
    final cache = source.indexOf('final cacheReady =');
    final audioSession = source.indexOf('final audioSessionReady =');
    final firebase = source.indexOf('final firebaseReady =');
    final wait = source.indexOf('await Future.wait<void>([');

    expect(playback, greaterThanOrEqualTo(0));
    expect(notifications, greaterThan(playback));
    expect(storage, greaterThan(playback));
    expect(connectivity, greaterThan(playback));
    expect(cache, greaterThan(playback));
    expect(audioSession, greaterThan(playback));
    expect(firebase, greaterThan(playback));
    expect(wait, greaterThan(firebase));

    expect(source, contains('configureEnsureReady(_ensurePlaybackPlatform)'));
    expect(source, contains('cacheReady.then('));
    expect(source, contains('connectivityReady.then('));
    expect(source, contains('firebaseReady.then('));
  });
}
