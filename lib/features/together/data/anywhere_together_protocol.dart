import 'dart:convert';

/// Small peer-to-peer message envelope for Anywhere Together.
///
/// OTYA's server sees only WebRTC connection setup. Playback state, temporary
/// conversation, reactions, Moments and active-media metadata travel through
/// the encrypted WebRTC data channel instead of being stored in the backend.
class AnywhereTogetherPacket {
  static const int version = 1;
  static const int maxEncodedBytes = 16 * 1024;
  static const int maxIdLength = 96;

  static const Set<String> allowedTypes = {
    'hello',
    'playback',
    'media',
    'roster',
    'chat',
    'moment',
    'reaction',
    'ping',
    'pong',
    'bye',
  };

  final String id;
  final String type;
  final Map<String, dynamic> payload;

  const AnywhereTogetherPacket({
    required this.id,
    required this.type,
    required this.payload,
  });

  static String encode({
    required String id,
    required String type,
    Map<String, dynamic> payload = const {},
  }) {
    final cleanId = id.trim();
    final cleanType = type.trim().toLowerCase();
    if (cleanId.isEmpty || cleanId.length > maxIdLength) {
      throw ArgumentError.value(id, 'id', 'Invalid Anywhere Together packet id.');
    }
    if (!allowedTypes.contains(cleanType)) {
      throw ArgumentError.value(type, 'type', 'Unsupported Anywhere Together packet type.');
    }

    final encoded = jsonEncode({
      'v': version,
      'id': cleanId,
      'type': cleanType,
      'payload': payload,
    });
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw ArgumentError.value(
        utf8.encode(encoded).length,
        'payload',
        'Anywhere Together packets are limited to $maxEncodedBytes bytes.',
      );
    }
    return encoded;
  }

  static AnywhereTogetherPacket? decode(String raw) {
    if (raw.isEmpty || utf8.encode(raw).length > maxEncodedBytes) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if (json['v'] != version) return null;

      final id = json['id'];
      final type = json['type'];
      final payload = json['payload'];
      if (id is! String ||
          id.trim().isEmpty ||
          id.length > maxIdLength ||
          type is! String ||
          !allowedTypes.contains(type.trim().toLowerCase()) ||
          payload is! Map) {
        return null;
      }

      return AnywhereTogetherPacket(
        id: id.trim(),
        type: type.trim().toLowerCase(),
        payload: Map<String, dynamic>.from(payload),
      );
    } catch (_) {
      return null;
    }
  }
}
