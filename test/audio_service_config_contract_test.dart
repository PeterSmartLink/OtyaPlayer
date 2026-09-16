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
}
