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
  final player = File(
    'lib/features/player/presentation/video_player_screen.dart',
  ).readAsStringSync();

  test('Together discovers invitations addressed to the signed-in user', () {
    expect(client, contains('/api/together/invites'));
    expect(client, contains('pendingInvites()'));
    expect(sheet, contains('TogetherControlClient.instance.pendingInvites()'));
    expect(sheet, contains('invited you to watch Together'));
  });

  test('pending invitation joins without copying the secret link', () {
    expect(client, contains('normalizedInviteToken.isEmpty'));
    expect(client, contains('<String, Object?>{}'));
    expect(runtime, contains('String inviteToken = \'\''));
    expect(sheet, contains('_joinPending(TogetherRemoteRoom room)'));
    expect(sheet, contains('child: const Text(\'Join\')'));
  });

  test('legacy link remains a secondary fallback', () {
    expect(sheet, contains('\'Older invite link\''));
    expect(sheet, contains('labelText: \'Fallback private invite\''));
    expect(sheet, contains('\'Join from link\''));
  });

  test('Together rejects malformed control identifiers before network work', () {
    expect(client, contains(r"RegExp(r'^[A-Za-z0-9_-]{20,32}$')"));
    expect(client, contains('identity.isValidUsername(username)'));
    expect(client, contains('normalizedInviteToken.length > 256'));
    expect(client, contains('normalizedAfter.length > 64'));
    expect(client, contains("code: 'INVALID_ROOM_ID'"));
    expect(client, contains("code: 'INVALID_INVITE'"));
    expect(client, contains("code: 'INVALID_SIGNAL_CURSOR'"));
  });

  test('Together drops control-plane signals from another room', () {
    expect(client, contains('signal.roomId == normalizedRoomId'));
  });

  test('remote Together end restores local playback exactly once', () {
    expect(player, contains('bool _leavingTogetherSession = false;'));
    expect(player, contains('final endedGuestStream = wasActive &&'));
    expect(player, contains('unawaited(_leaveTogetherSession());'));
    expect(player, contains('if (_leavingTogetherSession) return;'));
    expect(player, contains('await player.open(Media(widget.mediaItem.filePath), play: false);'));
    expect(player, contains('_position = restorePosition;'));
  });

  test('join surface explains local-copy data saving', () {
    expect(
      sheet,
      contains('Matching local media is reused first to save mobile data.'),
    );
  });
}
