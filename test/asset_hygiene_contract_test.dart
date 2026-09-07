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

  test('legacy density launcher bitmaps cannot shadow the canonical Otya icon', () {
    for (final density in ['mdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final name in [
        'ic_launcher.png',
        'ic_launcher_background.png',
        'ic_launcher_foreground.png',
        'ic_launcher_monochrome.png',
      ]) {
        final path = 'android/app/src/main/res/mipmap-$density/$name';
        expect(File(path).existsSync(), isFalse, reason: '$path is retired');
      }
    }

    final launcher = File(
      'android/app/src/main/res/mipmap-anydpi/ic_launcher.xml',
    ).readAsStringSync();
    expect(launcher, contains('@drawable/otya_launcher_foreground'));

    final buildGradle = File('android/app/build.gradle').readAsStringSync();
    expect(buildGradle, contains('assets/branding/otya_app_icon.webp'));
    expect(buildGradle, contains('otya_launcher_source.webp'));
  });
}
