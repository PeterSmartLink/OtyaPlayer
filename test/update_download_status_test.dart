import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/core/services/update_download_status.dart';

void main() {
  test('unknown content length keeps progress indeterminate', () {
    final status = UpdateDownloadStatus.fromMap({
      'status': 'running', 'downloaded': 4000, 'total': -1,
    });
    expect(status.progress, isNull);
    expect(status.label, 'Downloading…');
    expect(status.isComplete, isFalse);
  });

  test('full byte count does not claim installation or completion', () {
    final status = UpdateDownloadStatus.fromMap({
      'status': 'running', 'downloaded': 120, 'total': 100,
    });
    expect(status.progress, 1.0);
    expect(status.isComplete, isFalse);
  });

  test('paused downloads remain active while missing and failed files can retry', () {
    expect(const UpdateDownloadStatus(status: 'paused').isActive, isTrue);
    for (final state in ['failed', 'missing']) {
      final status = UpdateDownloadStatus(status: state);
      expect(status.canRetry, isTrue);
      expect(status.isComplete, isFalse);
      expect(status.isActive, isFalse);
    }
  });

  test('only Android success marks a download ready', () {
    expect(const UpdateDownloadStatus(status: 'complete').isComplete, isTrue);
    expect(UpdateDownloadStatus.fromMap({}).isComplete, isFalse);
    expect(const UpdateDownloadStatus(downloaded: -1, total: 100).progress, 0.0);
  });
}
