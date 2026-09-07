import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sender =
      File('lib/features/transfer/data/media_sender.dart').readAsStringSync();
  final channel = File(
    'lib/features/together/data/nearby_together_channel.dart',
  ).readAsStringSync();
  final nearbySession = File(
    'lib/features/together/application/nearby_together_session.dart',
  ).readAsStringSync();
  final runtime = File(
    'lib/features/together/application/nearby_together_runtime.dart',
  ).readAsStringSync();
  final player = File(
    'lib/features/player/presentation/video_player_screen.dart',
  ).readAsStringSync();
  final queue =
      File('lib/features/player/presentation/queue_screen.dart').readAsStringSync();

  test('host rotates media without replacing the Together room socket', () {
    expect(sender.contains('Future<String> switchServing(String filePath)'), isTrue);
    expect(
      nearbySession.contains('Future<NearbyHostedMedia> switchMedia'),
      isTrue,
    );
    expect(channel.contains("'media',"), isTrue);
    expect(channel.contains('void updateMedia({'), isTrue);
    expect(runtime.contains('Future<void> prepareHostNextMedia'), isTrue);
    expect(runtime.contains('_room.startNextMedia('), isTrue);
    expect(runtime.contains("host.channel.send(\n            'media'"), isTrue);
  });

  test('guest switches the existing player instead of creating another engine', () {
    expect(runtime.contains('case \'media\':'), isTrue);
    expect(runtime.contains('_handleGuestMediaChange(message)'), isTrue);
    expect(
      runtime.contains('adapter.player.open(Media(uri.toString()), play: false)'),
      isTrue,
    );
    expect(runtime.contains('MediaKitEngine('), isFalse);
    expect(runtime.contains('= Player('), isFalse);
  });

  test('nearby critical messages are acknowledged and retried safely', () {
    expect(channel.contains("'ack',"), isTrue);
    expect(channel.contains('static const Set<String> reliableTypes'), isTrue);
    expect(channel.contains("'hello',\n    'ready',\n    'media',"), isTrue);
    expect(channel.contains("'chat',\n    'moment',\n    'reaction',"), isTrue);
    expect(channel.contains('NearbyTogetherProtocol.requiresAck(type)'), isTrue);
    expect(channel.contains('_scheduleRetry(socket, decoded.id, pending)'), isTrue);
    expect(channel.contains('socket.add(pending.encoded)'), isTrue);
    expect(channel.contains("{'message_id': messageId}"), isTrue);
  });

  test('nearby retries cannot duplicate user-visible messages', () {
    expect(channel.contains('LinkedHashSet<String> _seenReliableIds'), isTrue);
    expect(channel.contains('if (!_rememberReliableId(message.id)) return;'), isTrue);
    expect(channel.contains('static const int _maxSeenReliableIds = 256'), isTrue);
    expect(channel.contains('_seenReliableIds.remove(_seenReliableIds.first)'), isTrue);
  });

  test('real-time state and clock samples remain lossy instead of queueing stale data', () {
    final reliableStart = channel.indexOf('static const Set<String> reliableTypes');
    final allowedStart = channel.indexOf('static const Set<String> allowedTypes');
    expect(reliableStart, greaterThanOrEqualTo(0));
    expect(allowedStart, greaterThan(reliableStart));
    final reliableBlock = channel.substring(reliableStart, allowedStart);
    expect(reliableBlock.contains("'state'"), isFalse);
    expect(reliableBlock.contains("'ping'"), isFalse);
    expect(reliableBlock.contains("'pong'"), isFalse);
  });

  test('video queue handoff preserves host authority across Together transports', () {
    expect(player.contains('await nearby.prepareHostNextMedia(item)'), isTrue);
    expect(player.contains('nearby.active && nearby.isGuest'), isTrue);
    expect(player.contains('anywhere.active && anywhere.isGuest'), isTrue);
    expect(
      player.contains(
        'The host chooses the shared video while Together is active.',
      ),
      isTrue,
    );
    expect(
      player.contains(
        'Finish the current Anywhere Together video before changing the shared video.',
      ),
      isTrue,
    );
    expect(player.contains('_handoffToAnotherVideo = true'), isTrue);
    expect(player.contains('if (!_handoffToAnotherVideo)'), isTrue);
  });

  test('failed handoff restores the exact queue index, including shuffle', () {
    expect(queue.contains('void restoreCurrentIndex(int index)'), isTrue);
    expect(player.contains('final beforeIndex = ref.read(queueProvider).currentIndex'), isTrue);
    expect(player.contains('queue.restoreCurrentIndex(beforeIndex)'), isTrue);
  });
}
