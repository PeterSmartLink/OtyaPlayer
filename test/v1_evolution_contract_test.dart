import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release candidate uses the shared 1.1 version family', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull);
    final version = match!.group(1)!;
    expect(version, matches(RegExp(r'^1\.0\.0\+[1-9][0-9]*$')));
  });

  test('normal and direct-release CI require zero analyzer issues', () {
    final testWorkflow =
        File('.github/workflows/test-apk.yml').readAsStringSync();
    final directRelease =
        File('.github/workflows/release-apk.yml').readAsStringSync();

    expect(testWorkflow, contains('run: flutter analyze'));
    expect(testWorkflow, isNot(contains('--no-fatal-infos')));
    expect(directRelease, contains('run: flutter analyze'));
    expect(directRelease, isNot(contains('--no-fatal-infos')));
    expect(testWorkflow, contains('actions/checkout@v6'));
    expect(directRelease, contains('actions/checkout@v6'));
  });

  test('test APK verification uses the Android signing verifier', () {
    final workflow =
        File('.github/workflows/test-apk.yml').readAsStringSync();

    expect(workflow, contains('apksigner'));
    expect(workflow, contains('verify --verbose --print-certs'));
    expect(workflow, isNot(contains(r'keytool -printcert -jarfile "$APK"')));
  });

  test('production releases use immutable semantic-version build tags', () {
    final directRelease =
        File('.github/workflows/release-apk.yml').readAsStringSync();
    final release = File('.github/workflows/release.yml').readAsStringSync();

    expect(directRelease, contains('Verify semantic release identity'));
    expect(directRelease, contains(r'^1\.0\.0\+[1-9][0-9]*$'));
    expect(release, contains("- 'v*'"));
    expect(release, contains(r'^v1\.0\.0\+[1-9][0-9]*$'));
    expect(release, contains(r'^1\.0\.0\+[1-9][0-9]*$'));
    expect(release, contains('APP_VERSION='));
    expect(release, contains(r'test "$APP_VERSION" = "${RELEASE_TAG#v}"'));
    expect(release, contains('does not exactly match pubspec version'));
    expect(release, isNot(contains("test \"\$TAG\" = 'v1.0.0'")));
    expect(release, contains('actions/checkout@v6'));
  });

  test('retired Online Music cannot return as a release dependency', () {
    final env = File('lib/core/config/environment.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(env, isNot(contains('onlineMusicUrl')));
    expect(env, isNot(contains('JAMENDO')));
    expect(env, isNot(contains('SPOTIFY_CLIENT_ID')));
    expect(pubspec.toLowerCase(), isNot(contains('spotify')));
    expect(pubspec.toLowerCase(), isNot(contains('jamendo')));
  });
}
