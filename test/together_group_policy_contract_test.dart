import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final policy = File(
    'lib/features/together/application/together_policy.dart',
  ).readAsStringSync();
  final controller = File(
    'lib/features/together/application/together_session_controller.dart',
  ).readAsStringSync();

  test('small private groups are capped at four people', () {
    expect(policy, contains('maxParticipantsV1 = 4'));
    expect(policy, contains('maxInvitedFriendsV1 = maxParticipantsV1 - 1'));
    expect(controller, contains('TogetherPolicy.maxParticipantsV1'));
    expect(controller, contains('Together room is full.'));
  });

  test('group policy keeps mobile data conservative', () {
    expect(policy, contains('preferMatchingLocalMedia = true'));
    expect(policy, contains('nearbyPrefersLocalNetwork = true'));
    expect(policy, contains('remoteMediaStreamingIsFallback = true'));
  });
}
