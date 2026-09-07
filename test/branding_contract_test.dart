import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android launcher and Flutter UI use one canonical Otya identity', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final legacy = File(
      'android/app/src/main/res/mipmap-anydpi/ic_launcher.xml',
    ).readAsStringSync();
    final foreground = File(
      'android/app/src/main/res/drawable/otya_launcher_foreground.xml',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final logo = File('lib/shared/widgets/otya_logo_v2.dart')
        .readAsStringSync();
    final colors = File('lib/app/theme/app_colors.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher"'));
    expect(
      manifest,
      isNot(contains('android:icon="@drawable/otya_launcher_icon"')),
      reason: 'Modern Android launchers must receive the Otya launcher resource.',
    );

    expect(adaptive, contains('@drawable/otya_launcher_foreground'));
    expect(adaptive, contains('@color/otya_launcher_background'));
    expect(
      adaptive,
      isNot(contains('@drawable/otya_launcher_monochrome')),
      reason: 'Do not theme an opaque full-icon bitmap as a monochrome glyph.',
    );
    expect(legacy, contains('@drawable/otya_launcher_foreground'));
    expect(foreground, contains('@drawable/otya_launcher_source'));
    expect(
      foreground,
      isNot(contains('@drawable/otya_launcher_foreground_bitmap')),
      reason: 'The previously corrupted launcher PNG must not be active.',
    );

    expect(gradle, contains('assets/branding/otya_app_icon.webp'));
    expect(gradle, contains('prepareOtyaBrandResources'));
    expect(gradle, contains('otya_launcher_source.webp'));
    expect(logo, contains("'assets/branding/otya_app_icon.webp'"));
    expect(
      logo,
      isNot(contains("'assets/branding/otya_mark_current.png'")),
      reason: 'Flutter must not silently fall back from the corrupted old PNG.',
    );
    expect(pubspec, contains('- assets/branding/'));
    expect(colors, contains('brandCyan = Color(0xFF27E8FF)'));
    expect(colors, contains('brandBlue = Color(0xFF126BFF)'));
    expect(colors, contains('colors: [brandCyan, brandBlue, brandDeepBlue]'));

    expect(File('assets/branding/otya_app_icon.webp').existsSync(), isTrue);
    expect(
      File('assets/branding/otya_mark_current.png').existsSync(),
      isFalse,
      reason: 'Malformed retired product marks must not remain as dormant assets.',
    );

    expect(
      foreground,
      isNot(contains('M160,98 L138,117 L116,146')),
      reason: 'The retired folded white/grey mark must not return to launcher.',
    );
  });
}
