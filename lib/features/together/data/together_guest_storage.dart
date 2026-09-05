import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Storage locations used only by guest-side Nearby Together media caching.
class TogetherGuestStorage {
  TogetherGuestStorage._();

  static final instance = TogetherGuestStorage._();

  Future<Directory> cacheDirectory(String mediaFingerprint) async {
    final base = await getApplicationSupportDirectory();
    final normalized = mediaFingerprint.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final safe = normalized.length > 96
        ? normalized.substring(0, 96)
        : normalized;
    if (safe.isEmpty) {
      throw ArgumentError.value(mediaFingerprint, 'mediaFingerprint');
    }
    final directory = Directory('${base.path}/together_cache/$safe');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> nextReceivedFile(String suggestedName) async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/OTYA_Received');
    await directory.create(recursive: true);

    final clean = _cleanFileName(suggestedName);
    final dot = clean.lastIndexOf('.');
    final stem = dot > 0 ? clean.substring(0, dot) : clean;
    final extension = dot > 0 ? clean.substring(dot) : '.mp4';

    var candidate = File('${directory.path}/$stem$extension');
    var suffix = 2;
    while (await candidate.exists()) {
      candidate = File('${directory.path}/$stem ($suffix)$extension');
      suffix++;
    }
    return candidate;
  }

  String suggestedNameFromUpstream(Uri upstream) {
    final advertised = upstream.queryParameters['name'];
    if (advertised == null || advertised.trim().isEmpty) {
      return 'Together video.mp4';
    }
    return _cleanFileName(advertised);
  }

  static String _cleanFileName(String value) {
    var clean = value
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_')
        .trim();
    if (clean.isEmpty || clean == '.' || clean == '..') {
      clean = 'Together video.mp4';
    }
    if (clean.length > 120) {
      final dot = clean.lastIndexOf('.');
      final extension = dot > 0 && clean.length - dot <= 12
          ? clean.substring(dot)
          : '';
      final maxStem = 120 - extension.length;
      clean = '${clean.substring(0, maxStem)}$extension';
    }
    return clean;
  }
}
