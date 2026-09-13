import 'dart:convert';

import '../../../core/config/environment.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/http_client.dart';
import '../../../core/services/otya_identity_service.dart';

class TogetherRoomParticipantView {
  final String role;
  final bool connected;
  final String otyaId;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  const TogetherRoomParticipantView({
    required this.role,
    required this.connected,
    required this.otyaId,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  String get handle => '@$username';

  factory TogetherRoomParticipantView.fromJson(Map<String, dynamic> json) {
    String text(Object? value) => value is String ? value.trim() : '';
    String? optional(Object? value) {
      final clean = text(value);
      return clean.isEmpty ? null : clean;
    }

    return TogetherRoomParticipantView(
      role: text(json['role']),
      connected: json['connected'] == true,
      otyaId: text(json['otya_id']).toUpperCase(),
      username: text(json['username'])
          .replaceFirst(RegExp(r'^@+'), '')
          .toLowerCase(),
      displayName: optional(json['name']),
      avatarUrl: optional(json['avatar_url']),
    );
  }
}

class TogetherRemoteRoom {
  final String roomId;
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final TogetherRoomParticipantView host;
  final TogetherRoomParticipantView guest;

  const TogetherRemoteRoom({
    required this.roomId,
    required this.status,
    required this.host,
    required this.guest,
    this.createdAt,
    this.expiresAt,
  });

  factory TogetherRemoteRoom.fromJson(Map<String, dynamic> json) {
    final host = Map<String, dynamic>.from(json['host'] as Map? ?? const {});
    final guest = Map<String, dynamic>.from(json['guest'] as Map? ?? const {});
    return TogetherRemoteRoom(
      roomId: (json['room_id'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? '').trim(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      host: TogetherRoomParticipantView.fromJson(host),
      guest: TogetherRoomParticipantView.fromJson(guest),
    );
  }
}

class TogetherRoomCreation {
  final TogetherRemoteRoom room;
  final String inviteToken;

  const TogetherRoomCreation({
    required this.room,
    required this.inviteToken,
  });
}

class TogetherSignal {
  final String id;
  final String roomId;
  final String type;
  final Object? payload;
  final String senderRole;
  final DateTime? createdAt;

  const TogetherSignal({
    required this.id,
    required this.roomId,
    required this.type,
    required this.senderRole,
    this.payload,
    this.createdAt,
  });

  factory TogetherSignal.fromJson(Map<String, dynamic> json) => TogetherSignal(
        id: (json['id'] as String? ?? '').trim(),
        roomId: (json['room_id'] as String? ?? '').trim(),
        type: (json['type'] as String? ?? '').trim().toLowerCase(),
        payload: json['payload'],
        senderRole:
            (json['sender_role'] as String? ?? '').trim().toLowerCase(),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );
}

class TogetherControlResult<T> {
  final T? value;
  final String? error;
  final String? code;

  const TogetherControlResult({this.value, this.error, this.code});

  bool get ok => error == null;
}

/// HTTP control plane for remote/Anywhere Together.
///
/// This client never transports video/audio/chat payloads. It only creates a
/// private room and exchanges short-lived connection setup messages. Nearby
/// Together bypasses this class entirely so it can remain internet-free.
class TogetherControlClient {
  TogetherControlClient._();

  static final instance = TogetherControlClient._();

  static const _timeout = Duration(seconds: 15);
  static const _allowedSignalTypes = {'offer', 'answer', 'ice', 'bye'};
  static final RegExp _roomIdPattern = RegExp(r'^[A-Za-z0-9_-]{20,32}$');

  Uri get _roomsUri =>
      Uri.parse('${Environment.workerUrl}/api/together/rooms');
  Uri get _invitesUri =>
      Uri.parse('${Environment.workerUrl}/api/together/invites');

  Future<TogetherControlResult<TogetherRoomCreation>> createRoom(
    String inviteUsername,
  ) async {
    final identity = OtyaIdentityService.instance;
    final username = identity.normalizeUsername(inviteUsername);
    if (!identity.isValidUsername(username)) {
      return const TogetherControlResult(
        error:
            'Use 3–24 characters, start with a letter, and use only letters, numbers or underscore.',
        code: 'INVALID_USERNAME',
      );
    }

    final auth = await _authorization();
    if (auth == null) return _signedOut();

    try {
      final response = await AppHttpClient.instance.client
          .post(
            _roomsUri,
            headers: {
              'Authorization': auth,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'invite_username': username}),
          )
          .timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 201 || data?['room'] is! Map) {
        return _error(data, 'Could not create Together right now.');
      }
      final token = data?['invite_token'];
      if (token is! String || token.isEmpty) {
        return const TogetherControlResult(
          error: 'Together invite could not be created.',
          code: 'INVALID_RESPONSE',
        );
      }
      return TogetherControlResult(
        value: TogetherRoomCreation(
          room: TogetherRemoteRoom.fromJson(
            Map<String, dynamic>.from(data!['room'] as Map),
          ),
          inviteToken: token,
        ),
      );
    } catch (_) {
      return _networkError();
    }
  }

  Future<TogetherControlResult<TogetherRemoteRoom>> joinRoom({
    required String roomId,
    String inviteToken = '',
  }) async {
    final normalizedRoomId = roomId.trim();
    if (!_roomIdPattern.hasMatch(normalizedRoomId)) return _invalidRoom();
    final normalizedInviteToken = inviteToken.trim();
    if (normalizedInviteToken.length > 256) return _invalidInvite();

    final auth = await _authorization();
    if (auth == null) return _signedOut();

    try {
      final response = await AppHttpClient.instance.client
          .post(
            _roomUri(normalizedRoomId, 'join'),
            headers: {
              'Authorization': auth,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(
              normalizedInviteToken.isEmpty
                  ? <String, Object?>{}
                  : {'invite_token': normalizedInviteToken},
            ),
          )
          .timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 200 || data?['room'] is! Map) {
        return _error(data, 'Could not join Together.');
      }
      return TogetherControlResult(
        value: TogetherRemoteRoom.fromJson(
          Map<String, dynamic>.from(data!['room'] as Map),
        ),
      );
    } catch (_) {
      return _networkError();
    }
  }

  Future<TogetherControlResult<List<TogetherRemoteRoom>>>
      pendingInvites() async {
    final auth = await _authorization();
    if (auth == null) return _signedOut();
    try {
      final response = await AppHttpClient.instance.client.get(
        _invitesUri,
        headers: {'Authorization': auth},
      ).timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 200 || data?['invites'] is! List) {
        return _error(data, 'Could not load Together invitations.');
      }
      final invites = (data!['invites'] as List)
          .whereType<Map>()
          .map(
            (item) =>
                TogetherRemoteRoom.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((room) => _roomIdPattern.hasMatch(room.roomId))
          .toList(growable: false);
      return TogetherControlResult(value: invites);
    } catch (_) {
      return _networkError();
    }
  }

  Future<TogetherControlResult<TogetherRemoteRoom>> getRoom(
    String roomId,
  ) async {
    final normalizedRoomId = roomId.trim();
    if (!_roomIdPattern.hasMatch(normalizedRoomId)) return _invalidRoom();

    final auth = await _authorization();
    if (auth == null) return _signedOut();

    try {
      final response = await AppHttpClient.instance.client.get(
        _roomUri(normalizedRoomId),
        headers: {'Authorization': auth},
      ).timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 200 || data?['room'] is! Map) {
        return _error(data, 'Together room is unavailable.');
      }
      return TogetherControlResult(
        value: TogetherRemoteRoom.fromJson(
          Map<String, dynamic>.from(data!['room'] as Map),
        ),
      );
    } catch (_) {
      return _networkError();
    }
  }

  Future<TogetherControlResult<void>> closeRoom(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (!_roomIdPattern.hasMatch(normalizedRoomId)) return _invalidRoom();

    final auth = await _authorization();
    if (auth == null) return _signedOut();

    try {
      final response = await AppHttpClient.instance.client.delete(
        _roomUri(normalizedRoomId),
        headers: {'Authorization': auth},
      ).timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _error(data, 'Could not close Together.');
      }
      return const TogetherControlResult();
    } catch (_) {
      return _networkError();
    }
  }

  Future<TogetherControlResult<String>> sendSignal({
    required String roomId,
    required String type,
    Object? payload,
  }) async {
    final normalizedRoomId = roomId.trim();
    if (!_roomIdPattern.hasMatch(normalizedRoomId)) return _invalidRoom();

    final normalizedType = type.trim().toLowerCase();
    if (!_allowedSignalTypes.contains(normalizedType)) {
      return const TogetherControlResult(
        error: 'Unsupported Together signal.',
        code: 'INVALID_SIGNAL',
      );
    }

    final auth = await _authorization();
    if (auth == null) return _signedOut();

    try {
      final response = await AppHttpClient.instance.client
          .post(
            _roomUri(normalizedRoomId, 'signals'),
            headers: {
              'Authorization': auth,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'type': normalizedType, 'payload': payload}),
          )
          .timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 202) {
        return _error(data, 'Could not send Together connection data.');
      }
      final signalId = data?['signal_id'];
      if (signalId is! String || signalId.isEmpty) {
        return const TogetherControlResult(
          error: 'Together returned an invalid signal response.',
          code: 'INVALID_RESPONSE',
        );
      }
      return TogetherControlResult(value: signalId);
    } catch (_) {
      return _networkError();
    }
  }

  Future<TogetherControlResult<List<TogetherSignal>>> pollSignals({
    required String roomId,
    String? after,
  }) async {
    final normalizedRoomId = roomId.trim();
    if (!_roomIdPattern.hasMatch(normalizedRoomId)) return _invalidRoom();
    final normalizedAfter = after?.trim();
    if (normalizedAfter != null && normalizedAfter.length > 64) {
      return const TogetherControlResult(
        error: 'Invalid Together signal cursor.',
        code: 'INVALID_SIGNAL_CURSOR',
      );
    }

    final auth = await _authorization();
    if (auth == null) return _signedOut();

    try {
      final base = _roomUri(normalizedRoomId, 'signals');
      final uri = normalizedAfter == null || normalizedAfter.isEmpty
          ? base
          : base.replace(queryParameters: {'after': normalizedAfter});
      final response = await AppHttpClient.instance.client.get(
        uri,
        headers: {'Authorization': auth},
      ).timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 200 || data?['signals'] is! List) {
        return _error(data, 'Could not receive Together connection data.');
      }
      final signals = (data!['signals'] as List)
          .whereType<Map>()
          .map(
            (item) => TogetherSignal.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (signal) =>
                signal.id.isNotEmpty &&
                signal.roomId == normalizedRoomId &&
                _allowedSignalTypes.contains(signal.type),
          )
          .toList(growable: false);
      return TogetherControlResult(value: signals);
    } catch (_) {
      return _networkError();
    }
  }

  Uri _roomUri(String roomId, [String? action]) {
    final safeRoom = Uri.encodeComponent(roomId.trim());
    final suffix = action == null ? '' : '/${Uri.encodeComponent(action)}';
    return Uri.parse(
      '${Environment.workerUrl}/api/together/rooms/$safeRoom$suffix',
    );
  }

  Future<String?> _authorization() async {
    final token = await AuthService.instance.getValidToken();
    return token == null ? null : 'Bearer $token';
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static TogetherControlResult<T> _error<T>(
    Map<String, dynamic>? data,
    String fallback,
  ) {
    final message = data?['error'];
    final code = data?['code'];
    return TogetherControlResult(
      error: message is String && message.trim().isNotEmpty ? message : fallback,
      code: code is String ? code : null,
    );
  }

  static TogetherControlResult<T> _invalidRoom<T>() =>
      const TogetherControlResult(
        error: 'Invalid Together room identifier.',
        code: 'INVALID_ROOM_ID',
      );

  static TogetherControlResult<T> _invalidInvite<T>() =>
      const TogetherControlResult(
        error: 'Invalid or expired Together invite.',
        code: 'INVALID_INVITE',
      );

  static TogetherControlResult<T> _signedOut<T>() =>
      const TogetherControlResult(
        error: 'Sign in to use Anywhere Together.',
        code: 'SIGN_IN_REQUIRED',
      );

  static TogetherControlResult<T> _networkError<T>() =>
      const TogetherControlResult(
        error: 'Could not reach OTYA right now.',
        code: 'NETWORK_ERROR',
      );
}
