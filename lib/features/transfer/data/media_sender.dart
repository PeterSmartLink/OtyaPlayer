import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Pure Dart local HTTP sender for Otya Send.
///
/// No cloud relay is used. A cryptographically random one-time token protects
/// the serving URL, and Range requests allow a matching receiver to resume an
/// interrupted transfer without re-reading the entire file.
class MediaSender {
  static const int _preferredPort = 8080;
  static const int _chunkBytes = 256 * 1024;
  static const int _maxBatchItems = 200;
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
  List<File> _files = const <File>[];
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

  /// Starts the backwards-compatible single-file sender used by Together and
  /// older Otya Send links.
  Future<String> startServing(String filePath) async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final file = await _validatedMediaFile(filePath);
    final session = await _startServer(<File>[file]);
    return _buildMediaUrl(
      file: file,
      ip: session.ip,
      port: session.port,
      token: session.token,
    );
  }

  /// Starts one local sender for every selected song/video and returns a single
  /// QR-safe batch URL. Files are served individually rather than zipped, so
  /// Otya does not duplicate large media or need temporary archive storage.
  Future<String> startServingBatch(Iterable<String> filePaths) async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final seen = <String>{};
    final files = <File>[];
    for (final path in filePaths) {
      if (!seen.add(path)) continue;
      files.add(await _validatedMediaFile(path));
      if (files.length > _maxBatchItems) {
        throw const FormatException(
          'Otya Send can prepare up to 200 media items at a time.',
        );
      }
    }
    if (files.isEmpty) {
      throw const FormatException('Choose at least one song or video to send.');
    }

    final session = await _startServer(files);
    return 'http://${session.ip}:${session.port}/batch?t=${session.token}';
  }

  Future<_SenderSession> _startServer(List<File> files) async {
    final ip = await _getLocalIp();
    final token = _generateToken();
    final server = await _bindServer();

    _files = List<File>.unmodifiable(files);
    _localIp = ip;
    _token = token;
    _server = server;

    debugPrint(
      '[MediaSender] Otya Send server ready with ${files.length} item(s).',
    );
    server.listen(
      _handleRequest,
      onError: (Object e) => debugPrint('[MediaSender] Error: $e'),
      cancelOnError: false,
    );
    return _SenderSession(ip: ip, port: server.port, token: token);
  }

  /// Replaces the media behind an already-running local sender without
  /// restarting the HTTP server. Together uses this for host handoff/next media.
  Future<String> switchServing(String filePath) async {
    final server = _server;
    final ip = _localIp;
    if (server == null || ip == null) {
      throw StateError('Otya local media sender is not active.');
    }

    final file = await _validatedMediaFile(filePath);
    final token = _generateToken();
    _files = <File>[file];
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
      throw const FormatException(
        'Otya Send only shares supported music and video files.',
      );
    }
    final length = await file.length();
    if (length <= 0) {
      throw FileSystemException('Media file is empty', filePath);
    }
    return file;
  }

  String _buildMediaUrl({
    required File file,
    required String ip,
    required int port,
    required String token,
  }) {
    final name = Uri.encodeQueryComponent(_fileName(file));
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
    _files = const <File>[];
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

    final requestToken = req.uri.queryParameters['t'];
    final currentToken = _token;
    if (!_tokenMatches(requestToken, currentToken)) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden');
      await req.response.close();
      debugPrint('[MediaSender] Rejected an invalid transfer token.');
      return;
    }

    if (req.uri.path == '/batch') {
      await _serveBatchManifest(req, currentToken!);
      return;
    }

    final file = _fileForRequestPath(req.uri.path);
    if (file == null) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found');
      await req.response.close();
      return;
    }

    await _serveMedia(req, file);
  }

  File? _fileForRequestPath(String path) {
    final files = _files;
    if (files.isEmpty) return null;
    if (path == '/media') return files.first;

    final match = RegExp(r'^/media/([0-9]+)$').firstMatch(path);
    if (match == null) return null;
    final index = int.tryParse(match.group(1)!);
    if (index == null || index < 0 || index >= files.length) return null;
    return files[index];
  }

  Future<void> _serveBatchManifest(HttpRequest req, String token) async {
    final server = _server;
    final ip = _localIp;
    final files = _files;
    if (server == null || ip == null || files.isEmpty) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('No media');
      await req.response.close();
      return;
    }

    final items = <Map<String, Object>>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      items.add(<String, Object>{
        'name': _fileName(file),
        'bytes': await file.length(),
        'url': 'http://$ip:${server.port}/media/$i?t=$token',
      });
    }

    final payload = utf8.encode(jsonEncode(<String, Object>{
      'version': 1,
      'count': items.length,
      'files': items,
    }));
    final response = req.response;
    _secureHeaders(response);
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, payload.length)
      ..headers.set('X-Otya-Transfer', '1')
      ..headers.set('X-Otya-Transfer-Mode', 'batch');

    if (req.method != 'HEAD') response.add(payload);
    await response.close();
  }

  Future<void> _serveMedia(HttpRequest req, File file) async {
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

    final mimeType = _mimeType(file.path);
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

    response.headers.set(
      'Content-Disposition',
      'attachment; filename="${_fileName(file).replaceAll('"', '')}"',
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
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; frame-ancestors 'none'",
      );
  }

  bool _tokenMatches(String? provided, String? expected) {
    if (provided == null ||
        expected == null ||
        provided.length != expected.length) {
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
      'Connect both devices to the same Wi-Fi or hotspot before using Send.',
    );
  }

  String _fileName(File file) => file.uri.pathSegments.isNotEmpty
      ? file.uri.pathSegments.last
      : 'otya-transfer';

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

class _SenderSession {
  const _SenderSession({
    required this.ip,
    required this.port,
    required this.token,
  });

  final String ip;
  final int port;
  final String token;
}
