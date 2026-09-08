import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final onboarding = File(
    'lib/features/onboarding/onboarding_screen.dart',
  ).readAsStringSync();

  test('first run describes public Otya capabilities only', () {
    expect(onboarding, contains('Video & Music'));
    expect(onboarding, contains('Send nearby'));
    expect(onboarding, contains('Private by default'));
    expect(onboarding, contains('No account is required'));

    expect(onboarding, isNot(contains("title: 'Together'")));
    expect(onboarding, isNot(contains('watch with a friend')));
    expect(onboarding, isNot(contains('Watch Together')));
  });

  test('onboarding stays focused on one clear completion action', () {
    expect(onboarding, contains("'Start using Otya'"));
    expect(onboarding, contains("setBool('isFirstLaunch', false)"));
  });
}
