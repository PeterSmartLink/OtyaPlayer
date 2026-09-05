import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../transfer/data/transfer_security_policy.dart';
import 'media_fingerprint_service.dart';

enum TogetherStreamMode {
  streamOnly,
  streamAndSave,
}

/// Local loopback origin for Nearby Together guest playback.
///
/// The player reads from 127.0.0.1 while this proxy reads only OTYA's already
/// authenticated private-LAN `/media` source. In stream-only mode bytes are
/// forwarded without persistent caching. In stream-and-save mode requested
/// ranges are cached in fixed chunks so playback and the eventual saved file
/// reuse the same network bytes instead of downloading the movie twice.
class TogetherStreamCacheProxy {
  TogetherStreamCacheProxy({
    this.chunkBytes = 1024 * 1024,
  }) : assert(chunkBytes > 0);

  static const int manifestVersion = 1;
  static final RegExp _tokenPattern = RegExp(r'^[a-f0-9]{64}$');

  final int chunkBytes;
  final _progressController = StreamController<double>.broadcast();
  final Map<int, Future<File>> _inFlightChunks = {};

  HttpClient? _client;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _serverSubscription;
  Uri? _upstream;
  Directory? _cacheDirectory;
  TogetherStreamMode? _mode;
  String? _mediaFingerprint;
  String? _mimeType;
  String? _localToken;
  int _byteLength = 0;
  int _cachedBytes = 0;

  Stream<double> get progress => _progressController.stream;
  int get byteLength => _byteLength;
  int get cachedBytes => _cachedBytes;
  double get cachedFraction =>
      _byteLength <= 0 ? 0 : (_cachedBytes / _byteLength).clamp(0.0, 1.0);
  bool get isRunning => _server != null;
  bool get keepsVideo => _mode == TogetherStreamMode.streamAndSave;

  Uri get localUrl {
    final server = _server;
    final token = _localToken;
    if (server == null || token == null) {
      throw StateError('Together stream proxy has not started.');
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/together-stream',
      queryParameters: {'t': token},
    );
  }

  Future<Uri> start({
    required Uri upstream,
    required int byteLength,
    required String mediaFingerprint,
    required TogetherStreamMode mode,
    String? mimeType,
    Directory? cacheDirectory,
  }) async {
    if (!isAllowedTransferUri(upstream)) {
      throw ArgumentError.value(
        upstream,
        'upstream',
        'Together accepts only authenticated OTYA private-LAN media sources.',
      );
    }
    if (byteLength <= 0) {
      throw ArgumentError.value(byteLength, 'byteLength');
    }
    final fingerprint = mediaFingerprint.trim();
    if (fingerprint.isEmpty) {
      throw ArgumentError.value(mediaFingerprint, 'mediaFingerprint');
    }
    if (mode == TogetherStreamMode.streamAndSave && cacheDirectory == null) {
      throw ArgumentError('Stream & Save requires a cache directory.');
    }

    await stop(deleteCache: false);

    _client = HttpClient()
      ..autoUncompress = false
      ..maxConnectionsPerHost = 4;
    _upstream = upstream;
    _byteLength = byteLength;
    _mediaFingerprint = fingerprint;
    _mode = mode;
    _mimeType = mimeType;
    _cacheDirectory = cacheDirectory;
    _localToken = _generateToken();
    _cachedBytes = 0;

    try {
      await _probeUpstream();
      if (mode == TogetherStreamMode.streamAndSave) {
        await _prepareCache(cacheDirectory!);
      }
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      _server = server;
      _serverSubscription = server.listen(
        (request) => unawaited(_handleLocalRequest(request)),
        onError: (_) {},
        cancelOnError: false,
      );
      return localUrl;
    } catch (_) {
      await stop(deleteCache: false);
      rethrow;
    }
  }

  Future<void> completeSave() async {
    if (_mode != TogetherStreamMode.streamAndSave) {
      throw StateError('This Together stream was started as Stream Only.');
    }
    final count = (_byteLength + chunkBytes - 1) ~/ chunkBytes;
    for (var index = 0; index < count; index++) {
      await _ensureChunk(index);
    }
    await _refreshCachedBytes();
  }

  /// Completes any still-missing chunks, verifies the assembled media identity,
  /// and atomically exposes the final file. No already-cached chunk is fetched
  /// again from the host.
  Future<File> finalizeTo(File destination) async {
    if (_mode != TogetherStreamMode.streamAndSave) {
      throw StateError('Stream Only has no persistent movie to finalize.');
    }
    if (await destination.exists()) {
      throw FileSystemException(
        'Refusing to overwrite an existing file',
        destination.path,
      );
    }

    await completeSave();
    await stop(deleteCache: false);

    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.otya-finalizing');
    if (await temporary.exists()) await temporary.delete();

    final sink = temporary.openWrite(mode: FileMode.write);
    try {
      final count = (_byteLength + chunkBytes - 1) ~/ chunkBytes;
      for (var index = 0; index < count; index++) {
        final chunk = _chunkFile(index);
        if (!await _isValidChunk(index, chunk)) {
          throw StateError('Together cache is incomplete.');
        }
        await sink.addStream(chunk.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    try {
      if (await temporary.length() != _byteLength) {
        throw StateError('Together saved media length does not match the host.');
      }
      final identity = await MediaFingerprintService.instance.identify(
        filePath: temporary.path,
        mimeType: _mimeType,
      );
      if (identity.byteLength != _byteLength ||
          identity.fingerprint != _mediaFingerprint) {
        throw StateError('Together saved media did not pass identity verification.');
      }

      final finalFile = await temporary.rename(destination.path);
      await _deleteCacheDirectory();
      return finalFile;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> stop({bool deleteCache = false}) async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close(force: true);
    _server = null;
    _client?.close(force: true);
    _client = null;
    _inFlightChunks.clear();
    _localToken = null;
    if (deleteCache) await _deleteCacheDirectory();
  }

  Future<void> dispose({bool deleteCache = false}) async {
    await stop(deleteCache: deleteCache);
    await _progressController.close();
  }

  Future<void> _probeUpstream() async {
    final upstream = _requireUpstream();
    final client = _requireClient();
    final request = await client.headUrl(upstream);
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    final response = await request.close();
    await response.drain<void>();

    if (response.statusCode != HttpStatus.ok ||
        response.headers.value('X-Otya-Transfer') != '1' ||
        response.contentLength != _byteLength) {
      throw StateError('Together host media source failed validation.');
    }
    _mimeType ??= response.headers.contentType?.mimeType;
  }

  Future<void> _prepareCache(Directory directory) async {
    final manifestFile = File('${directory.path}/manifest.json');
    var reusable = false;

    if (await manifestFile.exists()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is Map) {
          reusable = decoded['v'] == manifestVersion &&
              decoded['fingerprint'] == _mediaFingerprint &&
              decoded['byte_length'] == _byteLength &&
              decoded['chunk_bytes'] == chunkBytes;
        }
      } catch (_) {
        reusable = false;
      }
    }

    if (!reusable && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
    if (!reusable) {
      await manifestFile.writeAsString(
        jsonEncode({
          'v': manifestVersion,
          'fingerprint': _mediaFingerprint,
          'byte_length': _byteLength,
          'chunk_bytes': chunkBytes,
        }),
        flush: true,
      );
    }
    await _refreshCachedBytes();
  }

  Future<void> _handleLocalRequest(HttpRequest request) async {
    final response = request.response;
    _secureHeaders(response);

    try {
      if ((request.method != 'GET' && request.method != 'HEAD') ||
          request.uri.path != '/together-stream' ||
          !_tokenMatches(request.uri.queryParameters['t'], _localToken)) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }

      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        _byteLength,
      );
      if (range == null) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_byteLength');
        await response.close();
        return;
      }

      final start = range.$1;
      final end = range.$2;
      final partial = request.headers.value(HttpHeaders.rangeHeader) != null;
      final length = end - start + 1;

      response
        ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
        ..headers.set(HttpHeaders.contentLengthHeader, length)
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('X-Otya-Together', '1');
      if (_mimeType != null) {
        response.headers.contentType = ContentType.parse(_mimeType!);
      }
      if (partial) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$_byteLength',
        );
      }

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      if (_mode == TogetherStreamMode.streamAndSave) {
        await _serveFromCache(response, start, end);
      } else {
        await _proxyRange(response, start, end);
      }
    } catch (_) {
      try {
        if (!response.headers.chunkedTransferEncoding &&
            response.statusCode < HttpStatus.badRequest) {
          response.statusCode = HttpStatus.badGateway;
        }
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveFromCache(HttpResponse response, int start, int end) async {
    var cursor = start;
    while (cursor <= end) {
      final index = cursor ~/ chunkBytes;
      final chunkStart = index * chunkBytes;
      final chunkEnd = min(_byteLength - 1, chunkStart + chunkBytes - 1);
      final wantedEnd = min(end, chunkEnd);
      final chunk = await _ensureChunk(index);
      final localStart = cursor - chunkStart;
      final localEndExclusive = wantedEnd - chunkStart + 1;
      await response.addStream(chunk.openRead(localStart, localEndExclusive));
      cursor = wantedEnd + 1;
    }
  }

  Future<void> _proxyRange(HttpResponse response, int start, int end) async {
    final upstream = await _openUpstreamRange(start, end);
    await response.addStream(upstream);
  }

  Future<File> _ensureChunk(int index) {
    final existing = _inFlightChunks[index];
    if (existing != null) return existing;
    final future = _loadOrFetchChunk(index);
    _inFlightChunks[index] = future;
    return future.whenComplete(() => _inFlightChunks.remove(index));
  }

  Future<File> _loadOrFetchChunk(int index) async {
    final file = _chunkFile(index);
    if (await _isValidChunk(index, file)) return file;

    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.downloading');
    if (await temporary.exists()) await temporary.delete();

    final start = index * chunkBytes;
    if (start >= _byteLength) {
      throw RangeError.index(index, List.empty());
    }
    final end = min(_byteLength - 1, start + chunkBytes - 1);
    final expected = end - start + 1;
    final upstream = await _openUpstreamRange(start, end);

    var written = 0;
    final sink = temporary.openWrite(mode: FileMode.write);
    try {
      await for (final bytes in upstream) {
        written += bytes.length;
        if (written > expected) {
          throw StateError('Together host sent too many bytes.');
        }
        sink.add(bytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (written != expected) {
      if (await temporary.exists()) await temporary.delete();
      throw StateError('Together host range ended before all bytes arrived.');
    }

    final saved = await temporary.rename(file.path);
    await _refreshCachedBytes();
    return saved;
  }

  Future<HttpClientResponse> _openUpstreamRange(int start, int end) async {
    final client = _requireClient();
    final upstream = _requireUpstream();
    final request = await client.getUrl(upstream);
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();

    final expected = end - start + 1;
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (response.statusCode != HttpStatus.partialContent ||
        response.headers.value('X-Otya-Transfer') != '1' ||
        response.contentLength != expected ||
        contentRange != 'bytes $start-$end/$_byteLength') {
      await response.drain<void>();
      throw StateError('Together host returned an invalid byte range.');
    }
    return response;
  }

  Future<bool> _isValidChunk(int index, File file) async {
    if (!await file.exists()) return false;
    final start = index * chunkBytes;
    if (start >= _byteLength) return false;
    final expected = min(chunkBytes, _byteLength - start);
    return await file.length() == expected;
  }

  Future<void> _refreshCachedBytes() async {
    if (_mode != TogetherStreamMode.streamAndSave || _cacheDirectory == null) {
      _cachedBytes = 0;
      _emitProgress();
      return;
    }
    var total = 0;
    final count = (_byteLength + chunkBytes - 1) ~/ chunkBytes;
    for (var index = 0; index < count; index++) {
      final file = _chunkFile(index);
      if (await _isValidChunk(index, file)) total += await file.length();
    }
    _cachedBytes = total;
    _emitProgress();
  }

  void _emitProgress() {
    if (!_progressController.isClosed) {
      _progressController.add(cachedFraction);
    }
  }

  File _chunkFile(int index) {
    final directory = _cacheDirectory;
    if (directory == null) throw StateError('Together cache is unavailable.');
    return File(
      '${directory.path}/chunk_${index.toString().padLeft(8, '0')}.bin',
    );
  }

  Future<void> _deleteCacheDirectory() async {
    final directory = _cacheDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _cachedBytes = 0;
    _emitProgress();
  }

  HttpClient _requireClient() {
    final client = _client;
    if (client == null) throw StateError('Together stream proxy is stopped.');
    return client;
  }

  Uri _requireUpstream() {
    final upstream = _upstream;
    if (upstream == null) throw StateError('Together upstream is unavailable.');
    return upstream;
  }

  static (int, int)? _parseRange(String? header, int length) {
    if (length <= 0) return null;
    if (header == null || header.isEmpty) return (0, length - 1);
    if (!header.startsWith('bytes=') || header.contains(',')) return null;
    final value = header.substring(6).trim();
    final dash = value.indexOf('-');
    if (dash < 0) return null;
    final left = value.substring(0, dash).trim();
    final right = value.substring(dash + 1).trim();

    if (left.isEmpty) {
      final suffix = int.tryParse(right);
      if (suffix == null || suffix <= 0) return null;
      final take = min(suffix, length);
      return (length - take, length - 1);
    }

    final start = int.tryParse(left);
    if (start == null || start < 0 || start >= length) return null;
    if (right.isEmpty) return (start, length - 1);
    final requestedEnd = int.tryParse(right);
    if (requestedEnd == null || requestedEnd < start) return null;
    return (start, min(requestedEnd, length - 1));
  }

  static void _secureHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer');
  }

  static String _generateToken() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static bool _tokenMatches(String? provided, String? expected) {
    if (provided == null ||
        expected == null ||
        !_tokenPattern.hasMatch(provided) ||
        provided.length != expected.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < provided.length; i++) {
      difference |= provided.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}
