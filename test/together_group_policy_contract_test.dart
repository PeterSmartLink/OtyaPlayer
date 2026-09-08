import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final policy = File(
    'lib/features/together/application/together_policy.dart',
  ).readAsStringSync();
  final controller = File(
    'lib/features/together/application/together_session_controller.dart',
  ).readAsStringSync();

  test('small private groups have a four-person design ceiling', () {
    expect(policy, contains('maxParticipantsV1 = 4'));
    expect(policy, contains('maxInvitedFriendsV1 = maxParticipantsV1 - 1'));
    expect(controller, contains('TogetherPolicy.maxParticipantsV1'));
    expect(controller, contains('Together room is full.'));
  });

  test('group networking stays disabled until two-device Together passes', () {
    expect(policy, contains('requireTwoDeviceGateBeforeGroups = true'));
    expect(policy, contains('groupNetworkingEnabledV1 = false'));
  });

  test('group policy keeps mobile data conservative', () {
    expect(policy, contains('preferMatchingLocalMedia = true'));
    expect(policy, contains('nearbyPrefersLocalNetwork = true'));
    expect(policy, contains('directP2pBeforeTurn = true'));
    expect(policy, contains('turnIsFallbackOnly = true'));
    expect(policy, contains('remoteMediaStreamingIsFallback = true'));
    expect(policy, contains('groupRequiresMatchingLocalMediaV1 = true'));
    expect(policy, contains('groupRemoteMediaStreamingEnabledV1 = false'));
    expect(policy, contains('requireMeasuredDataUsageBeforeExpansion = true'));
  });

  test('advanced research ideas remain staged off in v1', () {
    expect(policy, contains('swarmDistributionEnabledV1 = false'));
    expect(policy, contains('onDeviceTranscodingEnabledV1 = false'));
    expect(policy, contains('togetherSubscriptionsEnabledV1 = false'));
    expect(policy, contains('togetherVoiceChatEnabledV1 = false'));
    expect(policy, contains('keepSyncTrafficLightweight = true'));
  });
}
