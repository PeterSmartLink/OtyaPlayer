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
    expect(runtime.contains('Player('), isFalse);
  });

  test('video queue handoff preserves Together and gives host media control', () {
    expect(player.contains('await runtime.prepareHostNextMedia(item)'), isTrue);
    expect(player.contains('runtime.active && runtime.isGuest'), isTrue);
    expect(
      player.contains(
        'The host chooses the shared video while Together is active.',
      ),
      isTrue,
    );
    expect(player.contains('_handoffToAnotherVideo = true'), isTrue);
    expect(
      player.contains(
        'if (NearbyTogetherRuntime.instance.active) {\n      unawaited(NearbyTogetherRuntime.instance.stop())',
      ),
      isFalse,
    );
  });

  test('failed handoff restores the exact queue index, including shuffle', () {
    expect(queue.contains('void restoreCurrentIndex(int index)'), isTrue);
    expect(player.contains('final beforeIndex = ref.read(queueProvider).currentIndex'), isTrue);
    expect(player.contains('queue.restoreCurrentIndex(beforeIndex)'), isTrue);
  });
}
