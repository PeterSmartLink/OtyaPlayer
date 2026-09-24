import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production release must use current main and an already-aligned tag', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();

    expect(source, contains('git fetch origin refs/heads/main:refs/remotes/origin/main'));
    expect(source, contains(r'MAIN_SHA="$(git rev-parse refs/remotes/origin/main)"'));
    expect(source, contains(r'TAG_SHA="$(git rev-list -n 1 "$RELEASE_TAG")"'));
    expect(source, contains(r'test "$HEAD_SHA" = "$MAIN_SHA" || {'));
    expect(source, contains(r'test "$TAG_SHA" = "$MAIN_SHA" || {'));
    expect(source, isNot(contains('git tag -f')));
    expect(source, isNot(contains('git push --force origin')));

    final headGuard = source.indexOf(r'test "$HEAD_SHA" = "$MAIN_SHA" || {');
    final tagGuard = source.indexOf(r'test "$TAG_SHA" = "$MAIN_SHA" || {');
    final build = source.indexOf('- name: Build APKs and Play bundle from one production configuration');
    final publish = source.indexOf('- name: Publish verified APKs to R2 and release control plane');
    expect(headGuard, greaterThanOrEqualTo(0));
    expect(tagGuard, greaterThanOrEqualTo(0));
    expect(build, greaterThan(headGuard));
    expect(build, greaterThan(tagGuard));
    expect(publish, greaterThan(build));
  });

  test('manual production release always checks out main', () {
    final source = File('.github/workflows/release.yml').readAsStringSync();
    expect(
      source,
      contains('ref: refs/heads/main'),
    );
  });
}
