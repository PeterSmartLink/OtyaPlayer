/// A display snapshot from Android's background download service.
class UpdateDownloadStatus {
  final String status;
  final int downloaded;
  final int total;

  const UpdateDownloadStatus({
    this.status = 'none',
    this.downloaded = 0,
    this.total = -1,
  });

  factory UpdateDownloadStatus.fromMap(Map<Object?, Object?> value) {
    return UpdateDownloadStatus(
      status: value['status'] is String ? value['status'] as String : 'unknown',
      downloaded: (value['downloaded'] as num?)?.toInt() ?? 0,
      total: (value['total'] as num?)?.toInt() ?? -1,
    );
  }

  bool get isActive => const {'pending', 'running', 'paused'}.contains(status);
  bool get isComplete => status == 'complete';
  bool get canRetry => status == 'failed' || status == 'missing';
  double? get progress => total > 0
      ? (downloaded / total).clamp(0.0, 1.0).toDouble()
      : null;

  String get label {
    switch (status) {
      case 'pending': return 'Waiting to download…';
      case 'running':
        final value = progress;
        return value == null ? 'Downloading…' : 'Downloading ${(value * 100).round()}%';
      case 'paused': return 'Download paused. Android will retry when it can.';
      case 'complete': return 'Download ready. Open Downloads to install the update.';
      case 'failed': return 'Download failed. Check your connection and storage, then retry.';
      case 'missing': return 'The downloaded file is no longer available. Download it again.';
      default: return '';
    }
  }
}
