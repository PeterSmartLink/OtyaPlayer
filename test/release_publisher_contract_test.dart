import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release publisher verifies R2 object identity and cache policy', () {
    final script = File('scripts/publish_r2.sh').readAsStringSync();

    expect(script, contains('aws s3api head-object'));
    expect(script, contains('--query ContentLength'));
    expect(script, contains('--query ContentType'));
    expect(script, contains('--query CacheControl'));
    expect(
      script,
      contains('application/vnd.android.package-archive'),
    );
    expect(script, contains('public, max-age=31536000, immutable'));
    expect(script, contains('public, max-age=300, must-revalidate'));
    expect(script, contains('Upload content type mismatch'));
    expect(script, contains('Upload cache-control mismatch'));
  });

  test('release publisher keeps immutable files ahead of latest aliases', () {
    final script = File('scripts/publish_r2.sh').readAsStringSync();

    final immutableUpload = script.indexOf('ARM64_VERSIONED');
    final workflowStart = script.indexOf('WORKFLOW_ID=');
    final latestAlias = script.indexOf(
      'upload_and_verify "\$ARM64_APK" "Otya-arm64.apk"',
    );

    expect(immutableUpload, greaterThanOrEqualTo(0));
    expect(workflowStart, greaterThan(immutableUpload));
    expect(latestAlias, greaterThan(workflowStart));
  });
}
