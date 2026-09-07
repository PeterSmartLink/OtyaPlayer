import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public split APKs stay within the Otya release size budget', () {
    final publisher = File('scripts/publish_r2.sh').readAsStringSync();

    expect(publisher, contains('MAX_APK_BYTES=40000000'));
    expect(publisher, contains('WARN_APK_BYTES=35000000'));
    expect(publisher, contains(r'[ "$SIZE" -le "$MAX_APK_BYTES" ]'));
    expect(
      publisher,
      contains(r'Otya split APKs must stay at or below $MAX_APK_BYTES bytes'),
    );
    expect(
      publisher.indexOf(r'[ "$SIZE" -le "$MAX_APK_BYTES" ]'),
      lessThan(publisher.indexOf(r'upload_and_verify "$ARM64_APK"')),
    );
  });

  test('release validation retries only recognizable transient build failures', () {
    final workflow = File(
      '.github/workflows/release-mode-validation.yml',
    ).readAsStringSync();

    expect(workflow, contains('max_attempts=3'));
    expect(workflow, contains('build-attempt-${attempt}.log'));
    expect(workflow, contains('successful-build-attempt.txt'));
    expect(workflow, contains('HTTP response code: (408|429|5[0-9]{2})'));
    expect(
      workflow,
      contains('deterministic release-mode build failure; not retrying'),
    );
    expect(workflow, contains('Save release-mode evidence'));
  });
}
