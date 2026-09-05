import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/data/media_fingerprint_service.dart';
import 'package:otya_player/features/together/data/together_stream_cache_proxy.dart';

class _FakeOtyaRangeHost {
  _FakeOtyaRangeHost(this.bytes);

  final Uint8List bytes;
  HttpServer? _server;
  int getRequests = 0;
  final List<String> requestedRanges = [];

  static const token =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  Uri get uri => Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: _server!.port,
        path: '/media',
        queryParameters: {'t': token, 'name': 'movie.mp4'},
      );

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('X-Otya-Transfer', '1')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..contentType = ContentType('video', 'mp4');

    if (request.uri.path != '/media' ||
        request.uri.queryParameters['t'] != token) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }

    if (request.method == 'HEAD') {
      response
        ..statusCode = HttpStatus.ok
        ..contentLength = bytes.length;
      await response.close();
      return;
    }

    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    getRequests++;
    final raw = request.headers.value(HttpHeaders.rangeHeader);
    requestedRanges.add(raw ?? '');
    if (raw == null || !raw.startsWith('bytes=')) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }

    final parts = raw.substring(6).split('-');
    final start = int.parse(parts[0]);
    final end = int.parse(parts[1]);
    if (start < 0 || end < start || end >= bytes.length) {
      response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */${bytes.length}');
      await response.close();
      return;
    }

    final payload = bytes.sublist(start, end + 1);
    response
      ..statusCode = HttpStatus.partialContent
      ..contentLength = payload.length
      ..headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${bytes.length}',
      )
      ..add(payload);
    await response.close();
  }
}

Future<Uint8List> _readRange(Uri uri, int start, int end) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.partialContent);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('reuses a cached chunk for repeated player ranges', () async {
    final source = Uint8List.fromList(
      List<int>.generate(180000, (index) => (index * 17) % 251),
    );
    final host = _FakeOtyaRangeHost(source);
    await host.start();
    addTearDown(host.close);

    final sourceDir = await Directory.systemTemp.createTemp('otya-proxy-source-');
    final sourceFile = File('${sourceDir.path}/movie.mp4');
    await sourceFile.writeAsBytes(source, flush: true);
    addTearDown(() => sourceDir.delete(recursive: true));
    final identity = await MediaFingerprintService.instance.identify(
      filePath: sourceFile.path,
      mimeType: 'video/mp4',
    );

    final cache = await Directory.systemTemp.createTemp('otya-proxy-cache-');
    addTearDown(() async {
      if (await cache.exists()) await cache.delete(recursive: true);
    });
    final proxy = TogetherStreamCacheProxy(chunkBytes: 64 * 1024);
    addTearDown(() => proxy.dispose(deleteCache: true));

    final local = await proxy.start(
      upstream: host.uri,
      byteLength: source.length,
      mediaFingerprint: identity.fingerprint,
      mimeType: 'video/mp4',
      mode: TogetherStreamMode.streamAndSave,
      cacheDirectory: cache,
    );

    final first = await _readRange(local, 100, 900);
    expect(first, source.sublist(100, 901));
    expect(host.getRequests, 1);
    expect(host.requestedRanges.single, 'bytes=0-65535');

    final second = await _readRange(local, 4000, 9000);
    expect(second, source.sublist(4000, 9001));
    expect(host.getRequests, 1, reason: 'the same 64 KiB chunk must not download twice');
  });

  test('persistent chunk cache resumes without refetching completed chunks', () async {
    final source = Uint8List.fromList(
      List<int>.generate(150000, (index) => (index * 29) % 253),
    );
    final host = _FakeOtyaRangeHost(source);
    await host.start();
    addTearDown(host.close);

    final dir = await Directory.systemTemp.createTemp('otya-proxy-resume-');
    final sourceFile = File('${dir.path}/source.mp4');
    await sourceFile.writeAsBytes(source, flush: true);
    final cache = Directory('${dir.path}/cache');
    final identity = await MediaFingerprintService.instance.identify(
      filePath: sourceFile.path,
    );
    addTearDown(() => dir.delete(recursive: true));

    final firstProxy = TogetherStreamCacheProxy(chunkBytes: 32 * 1024);
    final firstLocal = await firstProxy.start(
      upstream: host.uri,
      byteLength: source.length,
      mediaFingerprint: identity.fingerprint,
      mode: TogetherStreamMode.streamAndSave,
      cacheDirectory: cache,
    );
    expect(await _readRange(firstLocal, 12, 400), source.sublist(12, 401));
    expect(host.getRequests, 1);
    await firstProxy.dispose(deleteCache: false);

    final secondProxy = TogetherStreamCacheProxy(chunkBytes: 32 * 1024);
    addTearDown(() => secondProxy.dispose(deleteCache: true));
    final secondLocal = await secondProxy.start(
      upstream: host.uri,
      byteLength: source.length,
      mediaFingerprint: identity.fingerprint,
      mode: TogetherStreamMode.streamAndSave,
      cacheDirectory: cache,
    );
    expect(await _readRange(secondLocal, 1000, 2000), source.sublist(1000, 2001));
    expect(host.getRequests, 1, reason: 'resume must reuse the completed first chunk');
  });

  test('final save fills only missing chunks and reproduces original bytes', () async {
    final source = Uint8List.fromList(
      List<int>.generate(210000, (index) => (index * 31 + 7) % 255),
    );
    final host = _FakeOtyaRangeHost(source);
    await host.start();
    addTearDown(host.close);

    final dir = await Directory.systemTemp.createTemp('otya-proxy-final-');
    final sourceFile = File('${dir.path}/source.mp4');
    await sourceFile.writeAsBytes(source, flush: true);
    final identity = await MediaFingerprintService.instance.identify(
      filePath: sourceFile.path,
      mimeType: 'video/mp4',
    );
    final cache = Directory('${dir.path}/cache');
    final destination = File('${dir.path}/received.mp4');
    addTearDown(() => dir.delete(recursive: true));

    const chunkBytes = 48 * 1024;
    final proxy = TogetherStreamCacheProxy(chunkBytes: chunkBytes);
    addTearDown(proxy.dispose);
    final local = await proxy.start(
      upstream: host.uri,
      byteLength: source.length,
      mediaFingerprint: identity.fingerprint,
      mimeType: 'video/mp4',
      mode: TogetherStreamMode.streamAndSave,
      cacheDirectory: cache,
    );

    expect(await _readRange(local, 100, 1200), source.sublist(100, 1201));
    expect(host.getRequests, 1);

    final finalFile = await proxy.finalizeTo(destination);
    expect(await finalFile.readAsBytes(), source);

    final expectedChunks = (source.length + chunkBytes - 1) ~/ chunkBytes;
    expect(host.getRequests, expectedChunks);
    expect(host.requestedRanges.toSet().length, expectedChunks,
        reason: 'each fixed chunk must cross the network at most once');
  });

  test('rejects non-OTYA or non-local upstream URLs before networking', () async {
    final proxy = TogetherStreamCacheProxy(chunkBytes: 1024);
    addTearDown(proxy.dispose);

    await expectLater(
      proxy.start(
        upstream: Uri.parse(
          'https://example.com/media?t=${_FakeOtyaRangeHost.token}',
        ),
        byteLength: 100,
        mediaFingerprint: 's1:fake',
        mode: TogetherStreamMode.streamOnly,
      ),
      throwsArgumentError,
    );
  });
}
