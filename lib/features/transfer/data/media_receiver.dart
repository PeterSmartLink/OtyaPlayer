import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otya_transfer_android/otya_transfer_android.dart';

import 'transfer_security_policy.dart';

typedef ProgressCallback = void Function(int bytesDownloaded, int totalBytes);

class OtyaTransferBatchItem {
  const OtyaTransferBatchItem({
    required this.name,
    required this.url,
    required this.sizeBytes,
  });

  final String name;
  final String url;
  final int sizeBytes;
}

/// MediaReceiver — restricted local HTTP downloader for Otya Send.
///
/// Incoming bytes are streamed directly to disk. The receiver accepts only
/// authenticated Otya media links on private/local IPv4 ranges, refuses
/// redirects, checks the sender marker/MIME/declared size, and resumes only
/// when a sidecar proves the partial belongs to the same transfer token.
class MediaReceiver {
  static const int _maxTransferBytes = 16 * 1024 * 1024 * 1024;
  static const int _maxBatchBytes = 64 * 1024 * 1024 * 1024;
  static const int _maxManifestBytes = 256 * 1024;
  static const int _maxBatchItems = 200;
  static const int _storageReserveBytes = 64 * 1024 * 1024;
  static const Set<String> _supportedExtensions = {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'webm',
    'ts',
    'mp3',
    'aac',
    'flac',
    'wav',
    'ogg',
    'm4a',
    'opus',
  };

  bool _cancelled = false;

  /// Reads and validates the small authenticated batch manifest behind a Send
  /// QR. Every returned media URL must remain on the exact same local sender,
  /// port and one-time token as the scanned batch URL.
  Future<List<OtyaTransferBatchItem>> discoverBatch(String url) async {
    final uri = Uri.parse(url);
    if (!isAllowedTransferBatchUri(uri)) {
      throw const FormatException('That code is not a valid Otya Send batch.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (_isRedirect(response.statusCode)) {
        await response.drain<void>();
        throw HttpException('Otya Send does not follow redirects.', uri: uri);
      }
      if (response.statusCode != HttpStatus.ok ||
          response.headers.value('X-Otya-Transfer') != '1' ||
          response.headers.value('X-Otya-Transfer-Mode') != 'batch') {
        await response.drain<void>();
        throw HttpException('The nearby endpoint is not an Otya batch sender.', uri: uri);
      }

      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType != 'application/json') {
        await response.drain<void>();
        throw HttpException('Otya batch metadata has an invalid content type.', uri: uri);
      }
      if (response.contentLength > _maxManifestBytes) {
        await response.drain<void>();
        throw HttpException('Otya batch metadata is too large.', uri: uri);
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > _maxManifestBytes) {
          throw HttpException('Otya batch metadata is too large.', uri: uri);
        }
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('Unsupported Otya Send batch format.');
      }
      final rawFiles = decoded['files'];
      if (rawFiles is! List || rawFiles.isEmpty || rawFiles.length > _maxBatchItems) {
        throw const FormatException('Otya Send batch has an invalid item count.');
      }

      final token = uri.queryParameters['t'];
      final items = <OtyaTransferBatchItem>[];
      final seenUrls = <String>{};
      var totalBatchBytes = 0;
      for (final raw in rawFiles) {
        if (raw is! Map) {
          throw const FormatException('Otya Send batch contains invalid media metadata.');
        }
        final name = _safeMediaName(raw['name']);
        final size = raw['bytes'];
        final rawUrl = raw['url'];
        if (size is! int || size <= 0 || size > _maxTransferBytes || rawUrl is! String) {
          throw const FormatException('Otya Send batch contains invalid media metadata.');
        }

        final itemUri = Uri.tryParse(rawUrl);
        if (itemUri == null ||
            !isAllowedTransferUri(itemUri) ||
            itemUri.path == '/together-stream' ||
            itemUri.host != uri.host ||
            itemUri.port != uri.port ||
            itemUri.queryParameters['t'] != token) {
          throw const FormatException('Otya Send batch tried to leave the verified local sender.');
        }

        final normalizedUrl = itemUri.toString();
        if (!seenUrls.add(normalizedUrl)) {
          throw const FormatException('Otya Send batch contains a duplicate media URL.');
        }

        totalBatchBytes += size;
        if (totalBatchBytes > _maxBatchBytes) {
          throw const FormatException('Otya Send batch is larger than the safe receive limit.');
        }

        items.add(OtyaTransferBatchItem(
          name: name,
          url: normalizedUrl,
          sizeBytes: size,
        ));
      }
      return List<OtyaTransferBatchItem>.unmodifiable(items);
    } finally {
      client.close(force: true);
    }
  }

  Future<File> download({
    required String url,
    required String savePath,
    ProgressCallback? onProgress,
  }) async {
    _cancelled = false;
    final uri = Uri.parse(url);
    if (!isAllowedTransferUri(uri) || uri.path == '/together-stream') {
      throw const FormatException(
        'Otya Send only accepts authenticated private local-network media links.',
      );
    }
    if (!_supportedExtensions.contains(_extension(savePath))) {
      throw const FormatException(
        'Otya Send only receives supported music and video files.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(minutes: 10);

    final fingerprint = _fingerprint(uri);
    final saveFile = await _destinationFor(savePath, fingerprint);
    await saveFile.parent.create(recursive: true);
    final sidecar = _sidecarFor(saveFile);

    var existingBytes = 0;
    if (await saveFile.exists() &&
        await sidecar.exists() &&
        await sidecar.readAsString() == fingerprint) {
      existingBytes = await saveFile.length();
      if (existingBytes > _maxTransferBytes) {
        throw FileSystemException(
          'Partial transfer exceeds Otya safety limit.',
          saveFile.path,
        );
      }
    } else {
      await sidecar.writeAsString(fingerprint, flush: true);
    }

    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();
      if (_isRedirect(response.statusCode)) {
        await response.drain<void>();
        throw HttpException('Otya Send does not follow redirects.', uri: uri);
      }
      if (response.headers.value('X-Otya-Transfer') != '1') {
        await response.drain<void>();
        throw HttpException(
          'The nearby endpoint is not an Otya Send sender.',
          uri: uri,
        );
      }

      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          existingBytes > 0) {
        final remoteLength = _lengthFromUnsatisfiedRange(response);
        await response.drain<void>();
        if (remoteLength != null &&
            remoteLength <= _maxTransferBytes &&
            existingBytes == remoteLength) {
          debugPrint(
            '[MediaReceiver] Existing partial exactly matches remote transfer.',
          );
          onProgress?.call(existingBytes, existingBytes);
          await _deleteSidecar(sidecar);
          return saveFile;
        }

        debugPrint('[MediaReceiver] Resume offset invalid; restarting transfer.');
        if (await saveFile.exists()) await saveFile.delete();
        await sidecar.writeAsString(fingerprint, flush: true);
        return download(
          url: url,
          savePath: saveFile.path,
          onProgress: onProgress,
        );
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Server returned ${response.statusCode}', uri: uri);
      }

      final contentType =
          response.headers.contentType?.mimeType.toLowerCase() ?? '';
      if (!contentType.startsWith('audio/') &&
          !contentType.startsWith('video/')) {
        await response.drain<void>();
        throw HttpException(
          'Otya Send rejected a non-media response.',
          uri: uri,
        );
      }

      final isResume = response.statusCode == HttpStatus.partialContent &&
          existingBytes > 0;
      if (!isResume) existingBytes = 0;

      final responseBytes = response.contentLength;
      if (responseBytes < 0) {
        await response.drain<void>();
        throw HttpException(
          'Otya Send requires a known file size.',
          uri: uri,
        );
      }
      final totalBytes = existingBytes + responseBytes;
      if (totalBytes <= 0 || totalBytes > _maxTransferBytes) {
        await response.drain<void>();
        throw HttpException(
          'Transfer size is outside Otya safety limits.',
          uri: uri,
        );
      }

      final availableBytes =
          await OtyaTransferAndroid.availableBytes(saveFile.parent.path);
      final requiredAvailable = responseBytes + _storageReserveBytes;
      if (availableBytes != null && availableBytes < requiredAvailable) {
        await response.drain<void>();
        throw InsufficientTransferStorageException(
          requiredBytes: requiredAvailable,
          availableBytes: availableBytes,
        );
      }

      var downloaded = existingBytes;
      sink = saveFile.openWrite(
        mode: isResume ? FileMode.append : FileMode.writeOnly,
      );
      onProgress?.call(downloaded, totalBytes);

      await for (final chunk in response) {
        if (_cancelled) {
          debugPrint('[MediaReceiver] Cancelled; partial kept for safe resume.');
          break;
        }
        downloaded += chunk.length;
        if (downloaded > _maxTransferBytes || downloaded > totalBytes) {
          throw HttpException(
            'Otya Send exceeded the declared safe size.',
            uri: uri,
          );
        }
        sink.add(chunk);
        onProgress?.call(downloaded, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (_cancelled) throw const TransferCancelledException();
      if (downloaded != totalBytes) {
        throw HttpException(
          'Transfer ended early ($downloaded of $totalBytes bytes)',
          uri: uri,
        );
      }

      await _deleteSidecar(sidecar);
      debugPrint('[MediaReceiver] Saved to ${saveFile.path} ($downloaded bytes)');
      return saveFile;
    } catch (_) {
      await sink?.close();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  String _safeMediaName(Object? raw) {
    if (raw is! String) {
      throw const FormatException('Otya Send item has no valid file name.');
    }
    final name = raw
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    if (name.isEmpty ||
        name.length > 240 ||
        !_supportedExtensions.contains(_extension(name))) {
      throw const FormatException('Otya Send item has an unsupported file name.');
    }
    return name;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == 308;

  int? _lengthFromUnsatisfiedRange(HttpClientResponse response) {
    final header = response.headers.value(HttpHeaders.contentRangeHeader);
    if (header == null) return null;
    final match = RegExp(r'^bytes \*/(\d+)$').firstMatch(header.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String _fingerprint(Uri uri) {
    final token = uri.queryParameters['t'] ?? '';
    return '${uri.host}:${uri.port}${uri.path}|$token';
  }

  String _extension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  File _sidecarFor(File file) => File('${file.path}.otya-transfer');

  Future<File> _destinationFor(String requestedPath, String fingerprint) async {
    final requested = File(requestedPath);
    if (!await requested.exists()) return requested;

    final existingSidecar = _sidecarFor(requested);
    if (await existingSidecar.exists()) {
      try {
        if (await existingSidecar.readAsString() == fingerprint) return requested;
      } catch (_) {}
    }

    final slash = requestedPath.lastIndexOf(Platform.pathSeparator);
    final dir = slash >= 0 ? requestedPath.substring(0, slash + 1) : '';
    final name = slash >= 0 ? requestedPath.substring(slash + 1) : requestedPath;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';

    for (var i = 2; i <= 999; i++) {
      final candidate = File('$dir$base ($i)$ext');
      if (!await candidate.exists()) return candidate;
      final sidecar = _sidecarFor(candidate);
      if (await sidecar.exists()) {
        try {
          if (await sidecar.readAsString() == fingerprint) return candidate;
        } catch (_) {}
      }
    }

    return File('$dir${base}_${DateTime.now().millisecondsSinceEpoch}$ext');
  }

  Future<void> _deleteSidecar(File sidecar) async {
    try {
      if (await sidecar.exists()) await sidecar.delete();
    } catch (_) {}
  }

  void cancel() => _cancelled = true;
}

class TransferCancelledException implements Exception {
  const TransferCancelledException();

  @override
  String toString() => 'Transfer was cancelled.';
}

class InsufficientTransferStorageException implements Exception {
  const InsufficientTransferStorageException({
    required this.requiredBytes,
    required this.availableBytes,
  });

  final int requiredBytes;
  final int availableBytes;

  @override
  String toString() => 'Not enough free storage for this transfer.';
}
