import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../transfer/data/transfer_security_policy.dart';
import '../domain/media_identity.dart';

class NearbyTogetherInvite {
  final Uri uri;
  final String hostDisplayName;

  const NearbyTogetherInvite({
    required this.uri,
    required this.hostDisplayName,
  });
}

class NearbyTogetherMessage {
  final String type;
  final String id;
  final DateTime sentAt;
  final Map<String, dynamic> payload;

  const NearbyTogetherMessage({
    required this.type,
    required this.id,
    required this.sentAt,
    required this.payload,
  });

  factory NearbyTogetherMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return NearbyTogetherMessage(
      type: (json['type'] as String? ?? '').trim().toLowerCase(),
      id: (json['id'] as String? ?? '').trim(),
      sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }
}

/// Shared control-message contract for offline Nearby Together.
///
/// Movie bytes are not carried here. If the guest needs the host's media, the
/// existing OTYA LAN Range sender URL is advertised independently and the
/// player/transfer layer consumes that source.
abstract final class NearbyTogetherProtocol {
  static const int version = 1;
  static const int maxMessageBytes = 8 * 1024;

  static const Set<String> allowedTypes = {
    'hello',
    'ready',
    'state',
    'media',
    'chat',
    'moment',
    'reaction',
    'ping',
    'pong',
    'bye',
  };

  static String encode(String type, Map<String, dynamic> payload) {
    final normalized = type.trim().toLowerCase();
    if (!allowedTypes.contains(normalized)) {
      throw ArgumentError.value(type, 'type', 'Unsupported Nearby Together message');
    }
    final now = DateTime.now().toUtc();
    final random = Random.secure();
    final id = '${now.microsecondsSinceEpoch.toRadixString(36)}-'
        '${random.nextInt(0x7fffffff).toRadixString(36)}';
    final text = jsonEncode({
      'v': version,
      'type': normalized,
      'id': id,
      'sent_at': now.toIso8601String(),
      'payload': payload,
    });
    if (utf8.encode(text).length > maxMessageBytes) {
      throw const FormatException('Nearby Together message is too large.');
    }
    return text;
  }

  static NearbyTogetherMessage? decode(Object? raw) {
    if (raw is! String || utf8.encode(raw).length > maxMessageBytes) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if (json['v'] != version) return null;
      final type = (json['type'] as String? ?? '').trim().toLowerCase();
      if (!allowedTypes.contains(type)) return null;
      final message = NearbyTogetherMessage.fromJson(json);
      if (message.id.isEmpty) return null;
      return message;
    } catch (_) {
      return null;
    }
  }
}

class NearbyTogetherHost {
  static const String _path = '/together';
  static final RegExp _tokenPattern = RegExp(r'^[a-f0-9]{64}$');

  HttpServer? _server;
  WebSocket? _guest;
  String? _token;
  String? _displayName;
  String? _username;
  OtyaMediaIdentity? _media;
  Uri? _hostMediaUrl;
  final _messages = StreamController<NearbyTogetherMessage>.broadcast();
  final _connections = StreamController<bool>.broadcast();

  Stream<NearbyTogetherMessage> get messages => _messages.stream;
  Stream<bool> get connected => _connections.stream;
  bool get hasGuest => _guest != null;

  Future<NearbyTogetherInvite> start({
    required String displayName,
    String? username,
    required OtyaMediaIdentity media,
    required Uri hostMediaUrl,
  }) async {
    await stop();

    _validateMediaUrl(hostMediaUrl);

    final cleanDisplayName =
        displayName.trim().isEmpty ? 'OTYA user' : displayName.trim();
    final cleanUsername = username
        ?.trim()
        .replaceFirst(RegExp(r'^@+'), '')
        .toLowerCase();
    final ip = await _getLocalIp();
    final token = _generateToken();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: false);

    _server = server;
    _token = token;
    _displayName = cleanDisplayName;
    _username = cleanUsername;
    _media = media;
    _hostMediaUrl = hostMediaUrl;
    server.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );

    return NearbyTogetherInvite(
      hostDisplayName: cleanDisplayName,
      uri: Uri(
        scheme: 'ws',
        host: ip,
        port: server.port,
        path: _path,
        queryParameters: {'t': token},
      ),
    );
  }

  /// Updates what a newly connected/reconnected guest receives in `hello`.
  /// The WebSocket room itself remains alive while only the media advertisement
  /// changes.
  void updateMedia({
    required OtyaMediaIdentity media,
    required Uri hostMediaUrl,
  }) {
    _validateMediaUrl(hostMediaUrl);
    _media = media;
    _hostMediaUrl = hostMediaUrl;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final remote = request.connectionInfo?.remoteAddress.address ?? '';
    final provided = request.uri.queryParameters['t'];

    if (request.method != 'GET' ||
        request.uri.path != _path ||
        !WebSocketTransformer.isUpgradeRequest(request) ||
        !isPrivateTransferIpv4Host(remote, allowLoopback: false) ||
        !_tokenMatches(provided, _token)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write('Forbidden');
      await request.response.close();
      return;
    }

    if (_guest != null) {
      request.response
        ..statusCode = HttpStatus.conflict
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write('Together room is full');
      await request.response.close();
      return;
    }

    final displayName = _displayName;
    final media = _media;
    final hostMediaUrl = _hostMediaUrl;
    if (displayName == null || media == null || hostMediaUrl == null) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write('Together room is not ready');
      await request.response.close();
      return;
    }

    WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }

    _guest = socket;
    _connections.add(true);
    socket.pingInterval = const Duration(seconds: 20);

    await _sendSocket(socket, 'hello', {
      'display_name': displayName,
      if (_username != null && _username!.isNotEmpty) 'username': _username,
      'media': _mediaJson(media),
      'media_url': hostMediaUrl.toString(),
    });

    socket.listen(
      _acceptMessage,
      onDone: () => _guestDisconnected(socket),
      onError: (_) => _guestDisconnected(socket),
      cancelOnError: true,
    );
  }

  void _acceptMessage(Object? raw) {
    final message = NearbyTogetherProtocol.decode(raw);
    if (message != null && !_messages.isClosed) _messages.add(message);
  }

  void _guestDisconnected(WebSocket socket) {
    if (identical(_guest, socket)) {
      _guest = null;
      if (!_connections.isClosed) _connections.add(false);
    }
  }

  Future<void> send(String type, Map<String, dynamic> payload) async {
    final socket = _guest;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('No Nearby Together guest is connected.');
    }
    await _sendSocket(socket, type, payload);
  }

  Future<void> _sendSocket(
    WebSocket socket,
    String type,
    Map<String, dynamic> payload,
  ) async {
    if (socket.readyState != WebSocket.open) {
      throw StateError('Nearby Together socket is closed.');
    }
    socket.add(NearbyTogetherProtocol.encode(type, payload));
  }

  Future<void> stop() async {
    final guest = _guest;
    _guest = null;
    if (guest != null) {
      try {
        guest.add(NearbyTogetherProtocol.encode('bye', const {}));
        await guest.close(WebSocketStatus.normalClosure, 'Together ended');
      } catch (_) {}
    }
    await _server?.close(force: true);
    _server = null;
    _token = null;
    _displayName = null;
    _username = null;
    _media = null;
    _hostMediaUrl = null;
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _connections.close();
  }

  static Map<String, dynamic> _mediaJson(OtyaMediaIdentity media) => {
        'fingerprint': media.fingerprint,
        'byte_length': media.byteLength,
        if (media.duration != null) 'duration_ms': media.duration!.inMilliseconds,
        if (media.mimeType != null) 'mime_type': media.mimeType,
      };

  static void _validateMediaUrl(Uri hostMediaUrl) {
    if (!hostMediaUrl.isScheme('http') ||
        !isPrivateTransferIpv4Host(hostMediaUrl.host)) {
      throw ArgumentError('Nearby Together requires an OTYA private-LAN media URL.');
    }
  }

  static String _generateToken() {
    final rng = Random.secure();
    return List.generate(
      32,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static bool _tokenMatches(String? provided, String? expected) {
    if (provided == null || expected == null ||
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

  static Future<String> _getLocalIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (isPrivateTransferIpv4Host(address.address, allowLoopback: false)) {
          return address.address;
        }
      }
    }
    throw StateError('Connect to Wi-Fi or a hotspot to use Nearby Together.');
  }
}

class NearbyTogetherGuest {
  WebSocket? _socket;
  final _messages = StreamController<NearbyTogetherMessage>.broadcast();
  final _connections = StreamController<bool>.broadcast();

  Stream<NearbyTogetherMessage> get messages => _messages.stream;
  Stream<bool> get connected => _connections.stream;

  Future<void> connect(Uri inviteUri) async {
    await disconnect();
    if (!_isAllowedInvite(inviteUri)) {
      throw const FormatException('Invalid Nearby Together invite.');
    }

    final socket = await WebSocket.connect(inviteUri.toString()).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Nearby Together connection timed out.'),
    );
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;
    _connections.add(true);
    socket.listen(
      (raw) {
        final message = NearbyTogetherProtocol.decode(raw);
        if (message != null && !_messages.isClosed) _messages.add(message);
      },
      onDone: () => _disconnected(socket),
      onError: (_) => _disconnected(socket),
      cancelOnError: true,
    );
  }

  Future<void> send(String type, Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Nearby Together is not connected.');
    }
    socket.add(NearbyTogetherProtocol.encode(type, payload));
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        socket.add(NearbyTogetherProtocol.encode('bye', const {}));
        await socket.close(WebSocketStatus.normalClosure, 'Left Together');
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _connections.close();
  }

  void _disconnected(WebSocket socket) {
    if (identical(_socket, socket)) {
      _socket = null;
      if (!_connections.isClosed) _connections.add(false);
    }
  }

  static bool _isAllowedInvite(Uri uri) {
    final tokens = uri.queryParametersAll['t'];
    return uri.scheme == 'ws' &&
        uri.path == '/together' &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.port > 0 &&
        uri.port <= 65535 &&
        isPrivateTransferIpv4Host(uri.host, allowLoopback: false) &&
        tokens != null &&
        tokens.length == 1 &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(tokens.single);
  }
}
