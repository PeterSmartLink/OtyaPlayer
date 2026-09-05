import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public privacy copy matches connected Otya v1 behavior', () {
    final policy = File('docs/PRIVACY_POLICY.md').readAsStringSync();
    final inApp = File(
      'lib/features/settings/presentation/privacy_policy_screen.dart',
    ).readAsStringSync();

    for (final text in [policy, inApp]) {
      expect(text, contains('September 5, 2026'));
      expect(text, contains('Cloudflare'));
      expect(text, contains('Firebase'));
      expect(text, contains('Together'));
      expect(text, contains('Google Drive'));
      expect(text, contains('support@petersmartlink.com'));
      expect(text, isNot(contains('Privacy Policy — Played')));
      expect(text, isNot(contains('Messages you send to Next')));
      expect(text, isNot(contains('Appwrite')));
      expect(text, isNot(contains('AdMob')));
      expect(text, isNot(contains('We do NOT collect')));
      expect(text, isNot(contains('No usage analytics')));
    }
  });

  test('public project metadata uses current Otya identity and version', () {
    final security = File('SECURITY.md').readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();

    expect(
      security,
      matches(RegExp(r'first\s+public release line is `1\.0\.0`')),
    );
    expect(security, isNot(contains('1.6.0+10')));
    expect(contributing, contains('github.com/PeterSmartLink/OtyaPlayer'));
    expect(contributing, isNot(contains('gitlab.com/apk-v1')));
    expect(changelog, contains('## [1.0.0] — 2026-09-03'));
    expect(strings, contains('<string name="app_name">Otya</string>'));
    expect(strings, isNot(contains('OTYA Player')));
  });
}
