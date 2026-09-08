import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final client = File(
    'lib/features/together/data/together_control_client.dart',
  ).readAsStringSync();
  final runtime = File(
    'lib/features/together/application/anywhere_together_runtime.dart',
  ).readAsStringSync();
  final sheet = File(
    'lib/features/together/presentation/anywhere_together_sheet.dart',
  ).readAsStringSync();

  test('Together discovers invitations addressed to the signed-in user', () {
    expect(client, contains('/api/together/invites'));
    expect(client, contains('pendingInvites()'));
    expect(sheet, contains('TogetherControlClient.instance.pendingInvites()'));
    expect(sheet, contains('invited you to watch Together'));
  });

  test('pending invitation joins without copying the secret link', () {
    expect(
      client,
      contains('inviteToken.trim().isEmpty ? <String, Object?>{}'),
    );
    expect(runtime, contains('String inviteToken = \'\''));
    expect(sheet, contains('_joinPending(TogetherRemoteRoom room)'));
    expect(sheet, contains('child: const Text(\'Join\')'));
  });

  test('legacy link remains a secondary fallback', () {
    expect(sheet, contains('\'Older invite link\''));
    expect(sheet, contains('labelText: \'Fallback private invite\''));
    expect(sheet, contains('\'Join from link\''));
  });

  test('join surface explains local-copy data saving', () {
    expect(
      sheet,
      contains('Matching local media is reused first to save mobile data.'),
    );
  });
}
