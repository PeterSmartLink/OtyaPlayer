import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const mediaKitRevision = '9e1706898f15bcee98c125a2f4a7b88a4374dda7';
  const buildWorkflows = <String>[
    '.github/workflows/test-apk.yml',
    '.github/workflows/release-mode-validation.yml',
    '.github/workflows/release-apk.yml',
    '.github/workflows/play-closed-test.yml',
    '.github/workflows/release.yml',
  ];

  test('application dependency graph is committed and pins reviewed MediaKit', () {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue, reason: 'Applications must commit pubspec.lock.');

    final contents = lock.readAsStringSync();
    expect(contents, contains('  media_kit:'));
    expect(contents, contains('ref: "$mediaKitRevision"'));
    expect(contents, contains('resolved-ref: "$mediaKitRevision"'));
  });

  test('every Android validation and publication path rejects lock drift', () {
    for (final path in buildWorkflows) {
      final workflow = File(path).readAsStringSync();
      expect(workflow, contains('test -s pubspec.lock'), reason: path);
      expect(workflow, contains('flutter pub get'), reason: path);
      expect(workflow, contains("sha256sum pubspec.lock"), reason: path);
      expect(
        workflow,
        contains('git diff --exit-code -- pubspec.lock'),
        reason: path,
      );
      expect(
        workflow,
        contains('flutter pub get changed the committed dependency graph'),
        reason: path,
      );
    }
  });

  test('one-time dependency lock materialization machinery is gone', () {
    expect(
      File('.github/workflows/materialize-pubspec-lock.yml').existsSync(),
      isFalse,
    );
    expect(Directory('.github/lock-candidate').existsSync(), isFalse);

    final testWorkflow =
        File('.github/workflows/test-apk.yml').readAsStringSync();
    expect(testWorkflow, isNot(contains('Otya-dependency-lock-candidate')));
  });
}
