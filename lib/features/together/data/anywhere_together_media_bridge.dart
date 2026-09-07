import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'anywhere_together_peer.dart';

class AnywhereMediaDescriptor {
  final String fingerprint;
  final int byteLength;
  final String? mimeType;
  final int durationMs;

  const AnywhereMediaDescriptor({
    required this.fingerprint,
    required this.byteLength,
    required this.durationMs,
    this.mimeType,
  });

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'byte_length': byteLength,
        'duration_ms': durationMs,
        if (mimeType != null) 'mime_type': mimeType,
      };

  static AnywhereMediaDescriptor? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final fingerprint = json['fingerprint'];
    final byteLength = json['byte_length'];
    final durationMs = json['duration_ms'];
    final mimeType = json['mime_type'];
    if (fingerprint is! String ||
        fingerprint.trim().isEmpty ||
        byteLength is! int ||
        byteLength <= 0 ||
        durationMs is! int ||
        durationMs < 0 ||
        (mimeType != null && mimeType is! String)) {
      return null;
    }
    return AnywhereMediaDescriptor(
      fingerprint: fingerprint.trim(),
      byteLength: byteLength,
      durationMs: durationMs,
      mimeType: mimeType is String && mimeType.trim().isNotEmpty
          ? mimeType.trim()
          : null,
    );
  }
}

abstract final class AnywhereMediaWire {
  static const int version = 1;
  static const int chunkBytes = 48 * 1024;
  static const int headerBytes = 14;
  static const int maxRequestTextBytes = 1024;
  static const int maxConcurrentRanges = 4;

  static const int dataFrame = 1;
  static const int endFrame = 2;
  static const int errorFrame = 3;

  static Uint8List frame({
    required int kind,
    required int requestId,
    required int offset,
    Uint8List? payload,
  }) {
    if (requestId < 0 || requestId > 0xffffffff) {
      throw RangeError.range(requestId, 0, 0xffffffff, 'requestId');
    }
    if (offset < 0) throw RangeError.value(offset, 'offset');
    if (kind != dataFrame && kind != endFrame && kind != errorFrame) {
      throw ArgumentError.value(kind, 'kind');
    }
    final body = payload ?? Uint8List(0);
    final output = Uint8List(headerBytes + body.length);
    final header = ByteData.view(output.buffer, output.offsetInBytes, headerBytes);
    header
      ..setUint8(0, version)
      ..setUint8(1, kind)
      ..setUint32(2, requestId, Endian.big)
      ..setUint64(6, offset, Endian.big);
    output.setRange(headerBytes, output.length, body);
    return output;
  }

  static AnywhereMediaFrame? parseFrame(Uint8List value) {
    if (value.length < headerBytes) return null;
    final header = ByteData.view(
      value.buffer,
      value.offsetInBytes,
      headerBytes,
    );
    if (header.getUint8(0) != version) return null;
    final kind = header.getUint8(1);
    if (kind != dataFrame && kind != endFrame && kind != errorFrame) {
      return null;
    }
    return AnywhereMediaFrame(
      kind: kind,
      requestId: header.getUint32(2, Endian.big),
      offset: header.getUint64(6, Endian.big),
      payload: value.length == headerBytes
          ? Uint8List(0)
          : Uint8List.sublistView(value, headerBytes),
    );
  }

  static Map<String, dynamic>? parseRequestText(String raw) {
    if (raw.isEmpty || utf8.encode(raw).length > maxRequestTextBytes) {
      return null;
    }
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final json = Map<String, dynamic>.from(value);
      if (json['v'] != version) return null;
      return json;
    } catch (_) {
      return null;
    }
  }
}

class AnywhereMediaFrame {
  final int kind;
  final int requestId;
  final int offset;
  final Uint8List payload;

  const AnywhereMediaFrame({
    required this.kind,
    required this.requestId,
    required this.offset,
    required this.payload,
  });
}

/// Host-side range responder. The selected file remains on the host phone;
/// only requested bytes cross the encrypted WebRTC media data channel.
class AnywhereTogetherMediaHost {
  AnywhereTogetherMediaHost({required this.peer});

  final AnywhereTogetherPeer peer;
  StreamSubscription<dynamic>? _messageSub;
  File? _file;
  int _byteLength = 0;
  final Set<int> _activeRequests = <int>{};
  final Set<int> _cancelledRequests = <int>{};

  Future<void> start(File file) async {
    await stop();
    if (!await file.exists()) {
      throw FileSystemException('Together media file is unavailable.', file.path);
    }
    final length = await file.length();
    if (length <= 0) {
      throw StateError('Together cannot stream an empty media file.');
    }
    _file = file;
    _byteLength = length;
    _messageSub = peer.mediaMessages.listen((message) {
      if (message.isBinary) return;
      unawaited(_acceptRequest(message.text));
    });
  }

  Future<void> stop() async {
    await _messageSub?.cancel();
    _messageSub = null;
    _file = null;
    _byteLength = 0;
    _activeRequests.clear();
    _cancelledRequests.clear();
  }

  Future<void> _acceptRequest(String raw) async {
    final request = AnywhereMediaWire.parseRequestText(raw);
    if (request == null) return;
    final type = request['type'];
    final requestId = request['request_id'];
    if (requestId is! int || requestId < 0 || requestId > 0xffffffff) return;

    if (type == 'cancel') {
      _cancelledRequests.add(requestId);
      return;
    }
    if (type != 'range') return;

    final start = request['start'];
    final end = request['end'];
    if (start is! int ||
        end is! int ||
        start < 0 ||
        end < start ||
        end >= _byteLength ||
        _activeRequests.contains(requestId)) {
      await _sendError(requestId, start is int && start >= 0 ? start : 0);
      return;
    }
    if (_activeRequests.length >= AnywhereMediaWire.maxConcurrentRanges) {
      await _sendError(requestId, start);
      return;
    }

    _activeRequests.add(requestId);
    try {
      await _serveRange(requestId, start, end);
    } catch (_) {
      try {
        await _sendError(requestId, start);
      } catch (_) {}
    } finally {
      _activeRequests.remove(requestId);
      _cancelledRequests.remove(requestId);
    }
  }

  Future<void> _serveRange(int requestId, int start, int end) async {
    final file = _file;
    if (file == null) throw StateError('Together host media is unavailable.');

    var offset = start;
    await for (final bytes in file.openRead(start, end + 1)) {
      if (_cancelledRequests.contains(requestId)) return;
      var cursor = 0;
      while (cursor < bytes.length) {
        if (_cancelledRequests.contains(requestId)) return;
        final take = min(
          AnywhereMediaWire.chunkBytes,
          bytes.length - cursor,
        );
        final payload = Uint8List.fromList(
          bytes.sublist(cursor, cursor + take),
        );
        await peer.sendMediaBinary(
          AnywhereMediaWire.frame(
            kind: AnywhereMediaWire.dataFrame,
            requestId: requestId,
            offset: offset,
            payload: payload,
          ),
        );
        offset += take;
        cursor += take;
      }
    }

    if (_cancelledRequests.contains(requestId)) return;
    if (offset != end + 1) {
      throw StateError('Together host range ended early.');
    }
    await peer.sendMediaBinary(
      AnywhereMediaWire.frame(
        kind: AnywhereMediaWire.endFrame,
        requestId: requestId,
        offset: offset,
      ),
    );
  }

  Future<void> _sendError(int requestId, int offset) {
    return peer.sendMediaBinary(
      AnywhereMediaWire.frame(
        kind: AnywhereMediaWire.errorFrame,
        requestId: requestId,
        offset: max(0, offset),
      ),
    );
  }
}

class _PendingGuestRange {
  _PendingGuestRange({
    required this.response,
    required this.start,
    required this.end,
  }) : cursor = start;

  final HttpResponse response;
  final int start;
  final int end;
  int cursor;
}

/// Guest-side loopback origin for OTYA's existing player. The player requests
/// ordinary HTTP byte ranges from 127.0.0.1; this bridge translates them into
/// encrypted WebRTC range requests to the host and streams replies back into
/// the same player instance.
class AnywhereTogetherMediaGuest {
  AnywhereTogetherMediaGuest({
    required this.peer,
    required this.descriptor,
  });

  final AnywhereTogetherPeer peer;
  final AnywhereMediaDescriptor descriptor;
  final Map<int, _PendingGuestRange> _pending = {};
  final Random _random = Random.secure();

  StreamSubscription<dynamic>? _messageSub;
  StreamSubscription<HttpRequest>? _serverSub;
  HttpServer? _server;
  String? _token;
  int _requestSequence = 0;

  bool get isRunning => _server != null;

  Uri get localUrl {
    final server = _server;
    final token = _token;
    if (server == null || token == null) {
      throw StateError('Anywhere Together media bridge has not started.');
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/anywhere-together-media',
      queryParameters: {'t': token},
    );
  }

  Future<Uri> start() async {
    await stop();
    if (descriptor.byteLength <= 0 || descriptor.fingerprint.trim().isEmpty) {
      throw StateError('Anywhere Together media metadata is invalid.');
    }
    _token = _randomToken();
    _messageSub = peer.mediaMessages.listen(_acceptMediaMessage);
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    _serverSub = server.listen(
      (request) => unawaited(_handleLocalRequest(request)),
      onError: (_) {},
      cancelOnError: false,
    );
    return localUrl;
  }

  Future<void> stop() async {
    await _serverSub?.cancel();
    _serverSub = null;
    await _server?.close(force: true);
    _server = null;
    await _messageSub?.cancel();
    _messageSub = null;
    _token = null;

    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final range in pending) {
      try {
        await range.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleLocalRequest(HttpRequest request) async {
    final response = request.response;
    _secureHeaders(response);

    try {
      if ((request.method != 'GET' && request.method != 'HEAD') ||
          request.uri.path != '/anywhere-together-media' ||
          request.uri.queryParameters['t'] != _token) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = _parseRange(rangeHeader, descriptor.byteLength);
      if (range == null) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */${descriptor.byteLength}',
          );
        await response.close();
        return;
      }

      final start = range.$1;
      final end = range.$2;
      final partial = rangeHeader != null;
      final length = end - start + 1;
      response
        ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentLengthHeader, length)
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('X-Otya-Together', 'anywhere');
      if (descriptor.mimeType != null) {
        try {
          response.headers.contentType = ContentType.parse(descriptor.mimeType!);
        } catch (_) {}
      }
      if (partial) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${descriptor.byteLength}',
        );
      }

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      if (!peer.mediaReady) {
        response.statusCode = HttpStatus.serviceUnavailable;
        await response.close();
        return;
      }

      final requestId = _nextRequestId();
      _pending[requestId] = _PendingGuestRange(
        response: response,
        start: start,
        end: end,
      );
      unawaited(response.done.whenComplete(() {
        if (_pending.remove(requestId) != null) {
          unawaited(_sendCancel(requestId));
        }
      }));

      await peer.sendMediaText(
        jsonEncode({
          'v': AnywhereMediaWire.version,
          'type': 'range',
          'request_id': requestId,
          'start': start,
          'end': end,
        }),
      );
    } catch (_) {
      try {
        if (response.statusCode < HttpStatus.badRequest) {
          response.statusCode = HttpStatus.badGateway;
        }
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _acceptMediaMessage(dynamic message) {
    if (message.isBinary != true) return;
    final binary = message.binary;
    if (binary is! Uint8List) return;
    final frame = AnywhereMediaWire.parseFrame(binary);
    if (frame == null) return;
    final pending = _pending[frame.requestId];
    if (pending == null) return;

    if (frame.kind == AnywhereMediaWire.dataFrame) {
      if (frame.offset != pending.cursor ||
          frame.payload.isEmpty ||
          frame.offset + frame.payload.length - 1 > pending.end) {
        unawaited(_failPending(frame.requestId));
        return;
      }
      pending.response.add(frame.payload);
      pending.cursor += frame.payload.length;
      return;
    }

    if (frame.kind == AnywhereMediaWire.endFrame) {
      if (frame.offset != pending.end + 1 || pending.cursor != pending.end + 1) {
        unawaited(_failPending(frame.requestId));
        return;
      }
      _pending.remove(frame.requestId);
      unawaited(pending.response.close());
      return;
    }

    if (frame.kind == AnywhereMediaWire.errorFrame) {
      unawaited(_failPending(frame.requestId));
    }
  }

  Future<void> _failPending(int requestId) async {
    final pending = _pending.remove(requestId);
    if (pending == null) return;
    try {
      await pending.response.close();
    } catch (_) {}
    await _sendCancel(requestId);
  }

  Future<void> _sendCancel(int requestId) async {
    if (!peer.mediaReady) return;
    try {
      await peer.sendMediaText(
        jsonEncode({
          'v': AnywhereMediaWire.version,
          'type': 'cancel',
          'request_id': requestId,
        }),
      );
    } catch (_) {}
  }

  int _nextRequestId() {
    _requestSequence = (_requestSequence + 1) & 0xffffffff;
    if (_requestSequence == 0) _requestSequence = 1;
    while (_pending.containsKey(_requestSequence)) {
      _requestSequence = (_requestSequence + 1) & 0xffffffff;
      if (_requestSequence == 0) _requestSequence = 1;
    }
    return _requestSequence;
  }

  String _randomToken() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static (int, int)? _parseRange(String? header, int length) {
    if (length <= 0) return null;
    if (header == null || header.trim().isEmpty) return (0, length - 1);
    if (header.contains(',')) return null;

    final match = RegExp(r'^bytes=(\d*)-(\d*)$', caseSensitive: false)
        .firstMatch(header.trim());
    if (match == null) return null;
    final rawStart = match.group(1) ?? '';
    final rawEnd = match.group(2) ?? '';
    if (rawStart.isEmpty && rawEnd.isEmpty) return null;

    if (rawStart.isEmpty) {
      final suffix = int.tryParse(rawEnd);
      if (suffix == null || suffix <= 0) return null;
      final count = min(suffix, length);
      return (length - count, length - 1);
    }

    final start = int.tryParse(rawStart);
    if (start == null || start < 0 || start >= length) return null;
    if (rawEnd.isEmpty) return (start, length - 1);
    final end = int.tryParse(rawEnd);
    if (end == null || end < start) return null;
    return (start, min(end, length - 1));
  }

  static void _secureHeaders(HttpResponse response) {
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
  }
}
