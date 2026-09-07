import 'dart:convert';

import '../../../core/config/environment.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/http_client.dart';

class TogetherIceConfiguration {
  final List<Map<String, dynamic>> iceServers;
  final bool relayAvailable;
  final bool degraded;
  final Duration expiresIn;

  const TogetherIceConfiguration({
    required this.iceServers,
    required this.relayAvailable,
    required this.degraded,
    required this.expiresIn,
  });

  Map<String, dynamic> get peerConnectionConfiguration => {
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
      };
}

class TogetherIceConfigResult {
  final TogetherIceConfiguration? value;
  final String? error;
  final String? code;

  const TogetherIceConfigResult({this.value, this.error, this.code});

  bool get ok => value != null && error == null;
}

/// Retrieves short-lived ICE configuration for one authenticated Together room.
/// Long-term TURN keys never leave the OTYA server.
class TogetherIceConfigClient {
  TogetherIceConfigClient._();

  static final instance = TogetherIceConfigClient._();
  static const _timeout = Duration(seconds: 15);

  Future<TogetherIceConfigResult> fetchForRoom(String roomId) async {
    final token = await AuthService.instance.getValidToken();
    if (token == null) {
      return const TogetherIceConfigResult(
        error: 'Sign in to use Anywhere Together.',
        code: 'SIGN_IN_REQUIRED',
      );
    }

    final safeRoom = Uri.encodeComponent(roomId.trim());
    if (safeRoom.isEmpty) {
      return const TogetherIceConfigResult(
        error: 'Together room is unavailable.',
        code: 'INVALID_ROOM',
      );
    }

    try {
      final response = await AppHttpClient.instance.client.get(
        Uri.parse('${Environment.workerUrl}/api/together/rooms/$safeRoom/ice'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      final data = _decode(response.body);
      if (response.statusCode != 200 || data == null) {
        return TogetherIceConfigResult(
          error: _errorMessage(data, 'Could not prepare Anywhere Together.'),
          code: data?['code'] as String?,
        );
      }

      final servers = _parseIceServers(data['ice_servers']);
      if (servers.isEmpty) {
        return const TogetherIceConfigResult(
          error: 'OTYA returned no usable connection routes.',
          code: 'INVALID_ICE_CONFIG',
        );
      }

      final seconds = data['expires_in'];
      final expiresIn = seconds is int && seconds > 0
          ? Duration(seconds: seconds)
          : const Duration(hours: 1);
      return TogetherIceConfigResult(
        value: TogetherIceConfiguration(
          iceServers: servers,
          relayAvailable: data['relay_available'] == true,
          degraded: data['degraded'] == true,
          expiresIn: expiresIn,
        ),
      );
    } catch (_) {
      return const TogetherIceConfigResult(
        error: 'Could not reach OTYA right now.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  static List<Map<String, dynamic>> _parseIceServers(Object? value) {
    if (value is! List) return const [];
    final parsed = <Map<String, dynamic>>[];

    for (final item in value.whereType<Map>()) {
      final json = Map<String, dynamic>.from(item);
      final rawUrls = json['urls'];
      final urls = <String>[];
      if (rawUrls is String) {
        urls.add(rawUrls);
      } else if (rawUrls is List) {
        urls.addAll(rawUrls.whereType<String>());
      }
      final cleanUrls = urls
          .map((url) => url.trim())
          .where((url) => RegExp(r'^(stun|turn|turns):', caseSensitive: false).hasMatch(url))
          .take(12)
          .toList(growable: false);
      if (cleanUrls.isEmpty) continue;

      final server = <String, dynamic>{'urls': cleanUrls};
      final username = json['username'];
      final credential = json['credential'];
      if (username is String && username.isNotEmpty) server['username'] = username;
      if (credential is String && credential.isNotEmpty) server['credential'] = credential;
      parsed.add(server);
      if (parsed.length >= 4) break;
    }

    return List<Map<String, dynamic>>.unmodifiable(parsed);
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static String _errorMessage(Map<String, dynamic>? data, String fallback) {
    final error = data?['error'];
    return error is String && error.trim().isNotEmpty ? error : fallback;
  }
}
