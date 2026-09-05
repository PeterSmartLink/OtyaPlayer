import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/data/media_fingerprint_service.dart';

void main() {
  test('same bytes under different filenames produce the same identity', () async {
    final dir = await Directory.systemTemp.createTemp('otya-fingerprint-');
    addTearDown(() => dir.delete(recursive: true));

    final bytes = Uint8List.fromList(
      List<int>.generate(256 * 1024, (index) => index % 251),
    );
    final a = File('${dir.path}/movie-one.mp4');
    final b = File('${dir.path}/renamed-copy.mp4');
    await a.writeAsBytes(bytes, flush: true);
    await b.writeAsBytes(bytes, flush: true);

    final first = await MediaFingerprintService.instance.identify(filePath: a.path);
    final second = await MediaFingerprintService.instance.identify(filePath: b.path);

    expect(first.sameMediaAs(second), isTrue);
    expect(first.fingerprint, startsWith('s1:'));
  });

  test('different sampled bytes do not match', () async {
    final dir = await Directory.systemTemp.createTemp('otya-fingerprint-');
    addTearDown(() => dir.delete(recursive: true));

    final a = File('${dir.path}/a.mp4');
    final b = File('${dir.path}/b.mp4');
    await a.writeAsBytes(List<int>.filled(128 * 1024, 1), flush: true);
    await b.writeAsBytes(List<int>.filled(128 * 1024, 2), flush: true);

    final first = await MediaFingerprintService.instance.identify(filePath: a.path);
    final second = await MediaFingerprintService.instance.identify(filePath: b.path);

    expect(first.sameMediaAs(second), isFalse);
  });

  test('file length participates in identity', () async {
    final dir = await Directory.systemTemp.createTemp('otya-fingerprint-');
    addTearDown(() => dir.delete(recursive: true));

    final a = File('${dir.path}/a.mp4');
    final b = File('${dir.path}/b.mp4');
    await a.writeAsBytes(List<int>.filled(64 * 1024, 9), flush: true);
    await b.writeAsBytes(List<int>.filled(64 * 1024 + 1, 9), flush: true);

    final first = await MediaFingerprintService.instance.identify(filePath: a.path);
    final second = await MediaFingerprintService.instance.identify(filePath: b.path);

    expect(first.sameMediaAs(second), isFalse);
  });
}
