import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct-install release is manual and uses Android APK verification', () {
    final source =
        File('.github/workflows/release-apk.yml').readAsStringSync();

    expect(source, contains('workflow_dispatch:'));
    expect(source, isNot(contains('branches: [v1-rebuild]')));
    expect(source, contains('apksigner'));
    expect(source, contains('verify --verbose --print-certs'));
    expect(source, contains('certificate SHA-256 digest'));
    expect(source, contains('configured Otya signing key'));
    expect(source, isNot(contains(r'keytool -printcert -jarfile "$APK"')));
  });

  test('production release tag must exactly match pubspec build', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();

    expect(source, contains('Prove tag, main and pubspec are the same build'));
    expect(source, contains('APP_VERSION='));
    expect(source, contains(r'test "$APP_VERSION" = "${RELEASE_TAG#v}"'));
    expect(source, contains('does not exactly match pubspec version'));
    expect(source, contains(r'^1\.0\.0\+[1-9][0-9]*$'));
    expect(source, contains('expected Otya 1.0.0+<positive build>'));
  });

  test('production release verifies both APK signers before publication', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();

    expect(
      source,
      contains(r'"$APKSIGNER" verify --verbose --print-certs "$ARM64"'),
    );
    expect(
      source,
      contains(r'"$APKSIGNER" verify --verbose --print-certs "$ARM32"'),
    );
    expect(source, contains('EXPECTED_SHA256'));
    expect(source, contains('ACTUAL_SHA256'));
    expect(source, contains('APK certificate does not match official Otya signing key'));
  });

  test('Play bundle signature is also verified against the Otya key', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();

    expect(source, contains(r'jarsigner -verify "$AAB"'));
    expect(source, contains(r'keytool -printcert -jarfile "$AAB"'));
    expect(source, contains('AAB_SHA256'));
    expect(source, contains('AAB certificate does not match official Otya signing key'));
  });
}
