import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('update notification stays compact and never renders raw changelog', () {
    final source = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(source, contains("final title = 'Otya \$version is ready';"));
    expect(
      source,
      contains('New features and improvements are ready. Tap to see what’s new.'),
    );
    expect(source, contains("summaryText: 'Official Otya update'"));

    expect(
      source,
      isNot(contains('BigTextStyleInformation(\n        releaseNotes,')),
      reason: 'Raw Markdown/changelog must never be expanded in Android shade.',
    );
    expect(
      source,
      isNot(contains("'Update available — v\$version',\n      releaseNotes,")),
      reason: 'Raw release notes must not be the notification body.',
    );
  });
}
