import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('.github/workflows/play-closed-test.yml').readAsStringSync();

  test('Play closed-test AAB is manual-only and built from current main', () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('push:')));
    expect(workflow, isNot(contains('pull_request:')));
    expect(workflow, contains('ref: refs/heads/main'));
    expect(workflow, contains('Play closed-test bundle must be built from current main'));
  });

  test('Play closed-test build uses official release bundle settings', () {
    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains("OTYA_SELF_UPDATE: 'false'"));
    expect(workflow, contains('source scripts/android-release-config.sh'));
    expect(workflow, contains(r'"${OTYA_RELEASE_DART_DEFINES[@]}"'));
    expect(workflow, contains('KEYSTORE_BASE64'));
    expect(workflow, contains('jarsigner -verify'));
    expect(workflow, contains('Play AAB certificate does not match the configured Otya signing key'));
    expect(workflow, contains(r'^1\.0\.0\+[1-9][0-9]*$'));
  });

  test('Play closed-test workflow has no public release or Cloudflare side effects', () {
    expect(workflow, isNot(contains('publish_r2.sh')));
    expect(workflow, isNot(contains('softprops/action-gh-release')));
    expect(workflow, isNot(contains('R2_ACCESS_KEY_ID')));
    expect(workflow, isNot(contains('CF_API_TOKEN')));
    expect(workflow, isNot(contains('aws s3')));
    expect(workflow, isNot(contains('git tag')));
    expect(workflow, isNot(contains('gh release')));
  });

  test('Play closed-test artifact is retained only as an Actions build artifact', () {
    expect(workflow, contains('actions/upload-artifact@v4'));
    expect(workflow, contains('Otya-Play-closed-test.aab'));
    expect(workflow, contains('retention-days: 14'));
  });
}
