import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Now Playing artwork cannot consume unbounded memory or cache files', () {
    final source = File(
      'lib/core/services/media_notification_service.dart',
    ).readAsStringSync();

    expect(source, contains('_maxArtworkBytes = 5 * 1024 * 1024'));
    expect(source, contains('_maxCachedArtworkFiles = 24'));
    expect(source, contains("final client = http.Client()"));
    expect(source, contains("final request = http.Request('GET', uri)"));
    expect(source, contains('await for (final chunk in response.stream)'));
    expect(source, contains('received > _maxArtworkBytes'));
    expect(source, contains("File('${target.path}.part')"));
    expect(source, contains('_pruneArtworkCache'));
    expect(source, contains('albumArtBytes.length > _maxArtworkBytes'));
    expect(source, isNot(contains('response.bodyBytes')));
  });
}
