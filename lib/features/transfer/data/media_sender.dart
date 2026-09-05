import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Pure Dart local HTTP sender for Otya Transfer.
///
/// No cloud relay is used. A cryptographically random one-time token protects
/// the serving URL, and Range requests allow a matching receiver to resume an
/// interrupted transfer without re-reading the entire file.
class MediaSender {
  static const int _preferredPort = 8080;
  static const int _chunkBytes = 256 * 1024;
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

  HttpServer? _server;
  String? _filePath;
  String? _localIp;
  String? _token;

  String? get localIp => _localIp;

  static String _generateToken() {
    final rng = Random.secure();
    return List.generate(
      32,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<String> startServing(String filePath) async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final file = await _validatedMediaFile(filePath);
    final ip = await _getLocalIp();
    final token = _generateToken();
    final server = await _bindServer();

    _filePath = filePath;
    _localIp = ip;
    _token = token;
    _server = server;

    debugPrint('[MediaSender] Otya Transfer server ready on local network.');
    server.listen(
      _handleRequest,
      onError: (Object e) => debugPrint('[MediaSender] Error: $e'),
      cancelOnError: false,
    );
    return _buildMediaUrl(
      file: file,
      ip: ip,
      port: server.port,
      token: token,
    );
  }

  /// Replaces the media behind an already-running local sender without
  /// restarting the HTTP server. The new file is fully validated before any
  /// active state changes, then the token rotates so stale URLs cannot request
  /// the next media. Requests already streaming the previous file may finish.
  Future<String> switchServing(String filePath) async {
    final server = _server;
    final ip = _localIp;
    if (server == null || ip == null) {
      throw StateError('Otya local media sender is not active.');
    }

    final file = await _validatedMediaFile(filePath);
    final token = _generateToken();
    _filePath = filePath;
    _token = token;

    return _buildMediaUrl(
      file: file,
      ip: ip,
      port: server.port,
      token: token,
    );
  }

  Future<File> _validatedMediaFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final extension = _extension(filePath);
    if (!_supportedExtensions.contains(extension)) {
      throw const FormatException('Otya Transfer only shares supported media files.');
    }
    return file;
  }

  String _buildMediaUrl({
    required File file,
    required String ip,
    required int port,
    required String token,
  }) {
    final name = Uri.encodeQueryComponent(
      file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'otya-transfer',
    );
    return 'http://$ip:$port/media?t=$token&name=$name';
  }

  Future<HttpServer> _bindServer() async {
    try {
      return await HttpServer.bind(
        InternetAddress.anyIPv4,
        _preferredPort,
        shared: true,
      );
    } on SocketException {
      return HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _localIp = null;
    _filePath = null;
    _token = null;
    debugPrint('[MediaSender] Stopped.');
  }

  Future<void> _handleRequest(HttpRequest req) async {
    if (req.method != 'GET' && req.method != 'HEAD') {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD')
        ..write('Method not allowed');
      await req.response.close();
      return;
    }

    if (req.uri.path != '/media') {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found');
      await req.response.close();
      return;
    }

    final requestToken = req.uri.queryParameters['t'];
    if (!_tokenMatches(requestToken, _token)) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden');
      await req.response.close();
      debugPrint('[MediaSender] Rejected an invalid transfer token.');
      return;
    }

    final filePath = _filePath;
    if (filePath == null) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('No file');
      await req.response.close();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found');
      await req.response.close();
      return;
    }

    final fileLength = await file.length();
    if (fileLength <= 0) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.noContent
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      await req.response.close();
      return;
    }

    final mimeType = _mimeType(filePath);
    final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = fileLength - 1;
    var isPartial = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final requestedStart = int.tryParse(parts.first);
      final requestedEnd = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1])
          : null;

      if (requestedStart == null ||
          requestedStart < 0 ||
          requestedStart >= fileLength ||
          (requestedEnd != null && requestedEnd < requestedStart)) {
        _secureHeaders(req.response);
        req.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileLength');
        await req.response.close();
        return;
      }

      start = requestedStart;
      end = (requestedEnd ?? fileLength - 1).clamp(start, fileLength - 1);
      isPartial = true;
    }

    final contentLength = end - start + 1;
    final response = req.response;
    _secureHeaders(response);
    response
      ..statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok
      ..headers.contentType = ContentType.parse(mimeType)
      ..headers.set(HttpHeaders.contentLengthHeader, contentLength)
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('X-Otya-Transfer', '1');

    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'otya-transfer';
    response.headers.set(
      'Content-Disposition',
      'attachment; filename="${fileName.replaceAll('"', '')}"',
    );

    if (isPartial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$fileLength',
      );
    }

    if (req.method == 'HEAD') {
      await response.close();
      return;
    }

    RandomAccessFile? raf;
    try {
      raf = await file.open();
      await raf.setPosition(start);
      var remaining = contentLength;
      while (remaining > 0) {
        final toRead = remaining < _chunkBytes ? remaining : _chunkBytes;
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        response.add(chunk);
        remaining -= chunk.length;
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      debugPrint('[MediaSender] Stream error: $e');
    } finally {
      await raf?.close();
      await response.close();
    }
  }

  void _secureHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
  }

  bool _tokenMatches(String? provided, String? expected) {
    if (provided == null || expected == null || provided.length != expected.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < provided.length; i++) {
      difference |= provided.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<String> _getLocalIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          final a = int.tryParse(parts[0]);
          final b = int.tryParse(parts[1]);
          final isPrivate = a == 10 ||
              (a == 192 && b == 168) ||
              (a == 172 && b != null && b >= 16 && b <= 31);
          if (isPrivate) return addr.address;
        }
      }
    } catch (e) {
      debugPrint('[MediaSender] Local network discovery failed: $e');
    }
    throw StateError(
      'Connect both devices to the same Wi-Fi or hotspot before using Transfer.',
    );
  }

  String _extension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  String _mimeType(String path) {
    const map = {
      'mp4': 'video/mp4',
      'mkv': 'video/x-matroska',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'ts': 'video/mp2t',
      'mp3': 'audio/mpeg',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'm4a': 'audio/mp4',
      'opus': 'audio/opus',
    };
    return map[_extension(path)] ?? 'application/octet-stream';
  }
}
