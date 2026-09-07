import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release publishing never rewrites tags and requires tag to match main', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();

    expect(source, isNot(contains('git tag -f')));
    expect(source, isNot(contains('git push --force origin')));
    expect(source, isNot(contains('Align v1.0.0 tag to verified main')));
    expect(source, contains(r'TAG_SHA="$(git rev-list -n 1 "$RELEASE_TAG")"'));
    expect(source, contains(r'test "$TAG_SHA" = "$MAIN_SHA"'));
    expect(
      source,
      contains(r'immutable tag $RELEASE_TAG does not point to current main'),
    );
    expect(source, contains("- 'v1.0.0+*'"));
  });
}
