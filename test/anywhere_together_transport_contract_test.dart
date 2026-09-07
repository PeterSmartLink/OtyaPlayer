import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/data/anywhere_together_protocol.dart';

void main() {
  test('Anywhere Together packet round-trips bounded peer data', () {
    final encoded = AnywhereTogetherPacket.encode(
      id: 'packet-1',
      type: 'chat',
      payload: {'text': 'Otya Together'},
    );

    final decoded = AnywhereTogetherPacket.decode(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.id, 'packet-1');
    expect(decoded.type, 'chat');
    expect(decoded.payload['text'], 'Otya Together');
  });

  test('Anywhere Together rejects unsupported and oversized packets', () {
    expect(
      () => AnywhereTogetherPacket.encode(
        id: 'packet-2',
        type: 'unsupported',
      ),
      throwsArgumentError,
    );
    expect(
      () => AnywhereTogetherPacket.encode(
        id: 'packet-3',
        type: 'chat',
        payload: {'text': 'x' * (AnywhereTogetherPacket.maxEncodedBytes + 1)},
      ),
      throwsArgumentError,
    );

    expect(
      AnywhereTogetherPacket.decode(
        '{"v":2,"id":"packet-4","type":"chat","payload":{}}',
      ),
      isNull,
    );
    expect(
      AnywhereTogetherPacket.decode(
        'x' * (AnywhereTogetherPacket.maxEncodedBytes + 1),
      ),
      isNull,
    );
  });

  test('Anywhere Together remains WebRTC data-channel only', () {
    final peerSource = File(
      'lib/features/together/data/anywhere_together_peer.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('flutter_webrtc: 1.6.1'));
    expect(peerSource, contains('createDataChannel'));
    expect(peerSource, isNot(contains('getUserMedia')));
    expect(peerSource, isNot(contains('getDisplayMedia')));
    expect(peerSource, isNot(contains('.addTrack(')));
    expect(peerSource, isNot(contains('.addStream(')));

    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(manifest, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
    expect(
      RegExp(
        r'android:name="android\.permission\.RECORD_AUDIO"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      RegExp(
        r'android:name="android\.permission\.MODIFY_AUDIO_SETTINGS"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
  });
}
