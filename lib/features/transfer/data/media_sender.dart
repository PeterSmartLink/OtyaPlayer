import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Pure Dart local HTTP sender for Otya Transfer.
///
/// No cloud relay is used. A cryptographically random one-time token protects
/// every serving URL, Range requests allow resume, and a tiny token-protected
/// local landing page lets a nearby phone receive with a browser even when it
/// does not have Otya installed yet.
class MediaSender {
  static const int _preferredPort = 8080;
  static const int _chunkBytes = 256 * 1024;
  static const Set<String> _supportedMediaExtensions = {
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
  String? _appApkPath;
  String? _localIp;
  String? _token;
  String? _mediaUrl;
  String? _pageUrl;
  String? _appUrl;

  String? get localIp => _localIp;
  int? get port => _server?.port;
  String? get mediaUrl => _mediaUrl;
  String? get pageUrl => _pageUrl;
  String? get appUrl => _appUrl;

  static String _generateToken() {
    final rng = Random.secure();
    return List.generate(
      32,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<String> startServing(
    String filePath, {
    String? appApkPath,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }
    final extension = _extension(filePath);
    if (!_supportedMediaExtensions.contains(extension)) {
      throw const FormatException(
        'Otya Transfer only shares supported local media from the library.',
      );
    }

    final safeApk = await _validatedApk(appApkPath);
    await _startSession(mediaPath: filePath, appApkPath: safeApk);
    return _mediaUrl!;
  }

  /// Starts a browser-only session that shares this installed standalone Otya
  /// APK. The Android bridge refuses split installs before this method is used.
  Future<String> startServingApp(String appApkPath) async {
    final safeApk = await _validatedApk(appApkPath);
    if (safeApk == null) {
      throw const FormatException('A standalone Otya APK is not available.');
    }
    await _startSession(appApkPath: safeApk);
    return _pageUrl!;
  }

  Future<String?> _validatedApk(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    if (_extension(path) != 'apk' || !await file.exists() || await file.length() <= 0) {
      return null;
    }
    return file.path;
  }

  Future<void> _startSession({
    String? mediaPath,
    String? appApkPath,
  }) async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final ip = await _getLocalIpWithRetry();
    _filePath = mediaPath;
    _appApkPath = appApkPath;
    _localIp = ip;
    _token = _generateToken();
    _server = await _bindServer();

    final base = 'http://$ip:${_server!.port}';
    _pageUrl = '$base/?t=$_token';
    if (mediaPath != null) {
      final file = File(mediaPath);
      final name = Uri.encodeQueryComponent(
        file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'otya-transfer',
      );
      _mediaUrl = '$base/media?t=$_token&name=$name';
    }
    if (appApkPath != null) {
      _appUrl = '$base/app?t=$_token';
    }

    _server!.listen(
      _handleRequest,
      onError: (Object error) => debugPrint('[MediaSender] Error: $error'),
      cancelOnError: false,
    );
    debugPrint(
      '[MediaSender] Otya Transfer ready on $ip:${_server!.port}.',
    );
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
    _appApkPath = null;
    _token = null;
    _mediaUrl = null;
    _pageUrl = null;
    _appUrl = null;
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
    if (!_tokenMatches(requestToken, _token)) {
      _secureHeaders(req.response);
      req.response
        ..statusCode = HttpStatus.forbidden
        ..write('Forbidden');
      await req.response.close();
      debugPrint('[MediaSender] Rejected an invalid transfer token.');
      return;
    }

    switch (req.uri.path) {
      case '/':
        await _serveLandingPage(req);
        return;
      case '/media':
        final path = _filePath;
        if (path == null) {
          await _notFound(req.response);
          return;
        }
        await _serveFile(req, path);
        return;
      case '/app':
        final path = _appApkPath;
        if (path == null) {
          await _notFound(req.response);
          return;
        }
        await _serveFile(req, path, downloadName: 'Otya.apk');
        return;
      default:
        await _notFound(req.response);
    }
  }

  Future<void> _serveLandingPage(HttpRequest req) async {
    final mediaPath = _filePath;
    final mediaName = mediaPath == null
        ? null
        : File(mediaPath).uri.pathSegments.lastOrNull ?? 'Shared media';
    final token = _token ?? '';

    final mediaButton = mediaPath == null
        ? ''
        : '<a class="button" href="/media?t=$token">Download ${_htmlEscape(mediaName!)}</a>';
    final appButton = _appApkPath == null
        ? ''
        : '<a class="button secondary" href="/app?t=$token">Download Otya APK</a>';

    final html = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Otya Transfer</title>
<style>
body{margin:0;background:#07111f;color:#f6fbff;font-family:system-ui,-apple-system,sans-serif}
main{max-width:520px;margin:0 auto;padding:48px 22px}
.mark{width:46px;height:46px;border-radius:15px;background:linear-gradient(135deg,#27e8ff,#126bff);display:grid;place-items:center;font-weight:900;color:#04101c}
h1{font-size:30px;margin:18px 0 8px}p{color:#a9bdd3;line-height:1.55}.card{margin-top:26px;padding:20px;border:1px solid #1f3953;border-radius:22px;background:#0d1b2b}.button{display:block;margin-top:12px;padding:15px 16px;text-align:center;border-radius:15px;background:#27e8ff;color:#04101c;text-decoration:none;font-weight:800}.button.secondary{background:#126bff;color:white}.note{font-size:12px;color:#7890a9;margin-top:20px}
</style>
</head>
<body><main>
<div class="mark">O</div>
<h1>Otya Transfer</h1>
<p>Direct from the nearby phone. This page works on the local Wi-Fi/hotspot and does not use the Internet.</p>
<div class="card">$mediaButton$appButton</div>
<p class="note">Keep the sending phone on this screen until the download finishes.</p>
</main></body></html>''';

    final bytes = utf8.encode(html);
    final response = req.response;
    _secureHeaders(response, allowInlineStyle: true);
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.contentLengthHeader, bytes.length)
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('X-Otya-Transfer', '1');
    if (req.method != 'HEAD') response.add(bytes);
    await response.close();
  }

  Future<void> _serveFile(
    HttpRequest req,
    String filePath, {
    String? downloadName,
  }) async {
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

    final safeName = (downloadName ??
            (file.uri.pathSegments.isNotEmpty
                ? file.uri.pathSegments.last
                : 'otya-transfer'))
        .replaceAll('"', '');
    response.headers.set(
      'Content-Disposition',
      'attachment; filename="$safeName"',
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
    } catch (error) {
      debugPrint('[MediaSender] Stream error: $error');
    } finally {
      await raf?.close();
      await response.close();
    }
  }

  Future<void> _notFound(HttpResponse response) async {
    _secureHeaders(response);
    response
      ..statusCode = HttpStatus.notFound
      ..write('Not found');
    await response.close();
  }

  void _secureHeaders(
    HttpResponse response, {
    bool allowInlineStyle = false,
  }) {
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        allowInlineStyle
            ? "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"
            : "default-src 'none'; frame-ancestors 'none'",
      );
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

  Future<String> _getLocalIpWithRetry() async {
    Object? lastError;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        return await _getLocalIp();
      } catch (error) {
        lastError = error;
        if (attempt < 9) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
    throw StateError(
      'No reachable local Wi-Fi/hotspot address is ready yet. $lastError',
    );
  }

  Future<String> _getLocalIp() async {
    final candidates = <_InterfaceCandidate>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (_isVirtualOrMobileInterface(name)) continue;
        for (final address in interface.addresses) {
          if (!_isPrivateIpv4(address.address)) continue;
          candidates.add(
            _InterfaceCandidate(
              name: interface.name,
              address: address.address,
              score: _interfaceScore(name),
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('[MediaSender] Local network discovery failed: $error');
    }

    candidates.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      return byScore != 0 ? byScore : a.name.compareTo(b.name);
    });
    if (candidates.isNotEmpty) {
      final chosen = candidates.first;
      debugPrint(
        '[MediaSender] Using ${chosen.name} (${chosen.address}) for Transfer.',
      );
      return chosen.address;
    }

    throw StateError(
      'Connect both devices to the same Wi-Fi or let Otya create an offline hotspot.',
    );
  }

  bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList(growable: false);
    if (octets.any((value) => value == null || value < 0 || value > 255)) {
      return false;
    }
    final a = octets[0]!;
    final b = octets[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  bool _isVirtualOrMobileInterface(String name) =>
      name == 'lo' ||
      name.startsWith('tun') ||
      name.startsWith('tap') ||
      name.startsWith('ppp') ||
      name.startsWith('rmnet') ||
      name.startsWith('ccmni') ||
      name.startsWith('clat') ||
      name.startsWith('v4-') ||
      name.startsWith('wg') ||
      name.contains('tailscale');

  int _interfaceScore(String name) {
    if (name.startsWith('ap') ||
        name.contains('wlan') ||
        name.contains('wifi')) {
      return 0;
    }
    if (name.contains('eth')) return 10;
    if (name.contains('usb')) return 20;
    return 50;
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
      'apk': 'application/vnd.android.package-archive',
    };
    return map[_extension(path)] ?? 'application/octet-stream';
  }

  String _htmlEscape(String value) => const HtmlEscape().convert(value);
}

class _InterfaceCandidate {
  const _InterfaceCandidate({
    required this.name,
    required this.address,
    required this.score,
  });

  final String name;
  final String address;
  final int score;
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;
}
