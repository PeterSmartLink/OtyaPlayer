import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media session is independent of ordinary notification setup', () {
    final source = File('lib/core/services/media_notification_service.dart')
        .readAsStringSync();
    expect(source, isNot(contains('initSharedNotificationsPlugin')));
    expect(source, contains('response.stream.timeout'));
    expect(source, contains('Timer(const Duration(seconds: 12), client.close)'));
    expect(source, contains('deadline.cancel()'));
  });
  test('stale artwork resolution cannot publish old Now Playing metadata', () {
    final source = File('lib/core/services/media_notification_service.dart')
        .readAsStringSync();

    expect(source, contains('int _metadataGeneration = 0;'));
    expect(source, contains('final generation = ++_metadataGeneration;'));
    expect(source, contains('if (generation != _metadataGeneration) return;'));
    expect(
      RegExp(r'if \(generation != _metadataGeneration\) return;')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(2),
      reason: 'Both path and bitmap artwork updates must reject stale results.',
    );
  });

  test('dismissing Now Playing invalidates pending metadata work', () {
    final source = File('lib/core/services/media_notification_service.dart')
        .readAsStringSync();
    final dismiss = source.substring(source.indexOf('Future<void> dismiss()'));

    expect(dismiss, contains('++_metadataGeneration;'));
    expect(dismiss, contains('clearMediaItem();'));
  });
}
