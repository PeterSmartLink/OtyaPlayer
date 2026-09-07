import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retired product assets do not remain bundled in Otya', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final path in [
      'assets/icons/play_store_512.png',
      'assets/branding/otya_mark.svg',
      'assets/animations/otya_ai_thinking.svg',
      'assets/themes/otya_mountains.jpg',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: '$path is retired');
    }

    expect(pubspec, isNot(contains('- assets/icons/')));
    expect(pubspec, isNot(contains('- assets/animations/')));
    expect(pubspec, isNot(contains('- assets/themes/')));
    expect(pubspec, contains('- assets/branding/'));
    expect(pubspec, contains('- assets/onboarding/'));
  });
}
