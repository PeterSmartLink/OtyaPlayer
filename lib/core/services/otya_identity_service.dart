import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/environment.dart';
import 'auth_service.dart';
import 'http_client.dart';

class OtyaPublicIdentity {
  final String? otyaId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const OtyaPublicIdentity({
    this.otyaId,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  String? get handle => username == null ? null : '@$username';

  factory OtyaPublicIdentity.fromJson(Map<String, dynamic> json) {
    String? clean(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return OtyaPublicIdentity(
      otyaId: clean(json['otya_id'])?.toUpperCase(),
      username: clean(json['username'])?.replaceFirst(RegExp(r'^@+'), '').toLowerCase(),
      displayName: clean(json['name']),
      avatarUrl: clean(json['avatar_url']),
    );
  }
}

class OtyaIdentityResult<T> {
  final T? value;
  final String? error;
  final String? code;
  final DateTime? availableAt;

  const OtyaIdentityResult({
    this.value,
    this.error,
    this.code,
    this.availableAt,
  });

  bool get ok => value != null && error == null;
}

/// Connected identity used by Together and other account-scoped OTYA features.
///
/// Local playback and Nearby transfer never depend on this service. Username is
/// additive to the existing public OTYA ID and is stored without the leading @.
class OtyaIdentityService {
  OtyaIdentityService._();

  static final instance = OtyaIdentityService._();

  static const String _cachedUsernameKey = 'otya_username';
  static final RegExp _usernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,23}$');

  Uri get _accountUri => Uri.parse('${Environment.workerUrl}/auth/account');

  String normalizeUsername(String value) =>
      value.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  bool isValidUsername(String value) =>
      _usernamePattern.hasMatch(normalizeUsername(value));

  Future<String?> cachedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_cachedUsernameKey)?.trim();
    return username?.isNotEmpty == true ? username : null;
  }

  Future<OtyaIdentityResult<OtyaPublicIdentity>> current() async {
    final token = await AuthService.instance.getValidToken();
    if (token == null) {
      return const OtyaIdentityResult(
        error: 'Sign in to use connected OTYA identity.',
        code: 'SIGN_IN_REQUIRED',
      );
    }

    try {
      final response = await AppHttpClient.instance.client.get(
        _accountUri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      final decoded = _decode(response.body);
      if (response.statusCode != 200 || decoded?['user'] is! Map) {
        return _errorFrom(decoded, fallback: 'Could not load your OTYA identity.');
      }

      final identity = OtyaPublicIdentity.fromJson(
        Map<String, dynamic>.from(decoded!['user'] as Map),
      );
      await _cache(identity.username);
      return OtyaIdentityResult(value: identity);
    } catch (_) {
      return const OtyaIdentityResult(
        error: 'Could not reach OTYA right now.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  Future<OtyaIdentityResult<OtyaPublicIdentity>> setUsername(String value) async {
    final username = normalizeUsername(value);
    if (!_usernamePattern.hasMatch(username)) {
      return const OtyaIdentityResult(
        error: 'Use 3–24 characters, start with a letter, and use only letters, numbers or underscore.',
        code: 'INVALID_USERNAME',
      );
    }

    final token = await AuthService.instance.getValidToken();
    if (token == null) {
      return const OtyaIdentityResult(
        error: 'Sign in before choosing an OTYA username.',
        code: 'SIGN_IN_REQUIRED',
      );
    }

    try {
      final response = await AppHttpClient.instance.client.patch(
        _accountUri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'username': username}),
      ).timeout(const Duration(seconds: 15));
      final decoded = _decode(response.body);
      if (response.statusCode != 200 || decoded?['user'] is! Map) {
        return _errorFrom(decoded, fallback: 'Could not save that username.');
      }

      final identity = OtyaPublicIdentity.fromJson(
        Map<String, dynamic>.from(decoded!['user'] as Map),
      );
      await _cache(identity.username);
      return OtyaIdentityResult(value: identity);
    } catch (_) {
      return const OtyaIdentityResult(
        error: 'Could not reach OTYA right now.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  Future<OtyaIdentityResult<OtyaPublicIdentity>> lookup(String value) async {
    final username = normalizeUsername(value);
    if (!_usernamePattern.hasMatch(username)) {
      return const OtyaIdentityResult(
        error: 'Enter a valid OTYA username.',
        code: 'INVALID_USERNAME',
      );
    }

    final token = await AuthService.instance.getValidToken();
    if (token == null) {
      return const OtyaIdentityResult(
        error: 'Sign in to invite someone by username.',
        code: 'SIGN_IN_REQUIRED',
      );
    }

    try {
      final uri = _accountUri.replace(
        queryParameters: {'lookup_username': username},
      );
      final response = await AppHttpClient.instance.client.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      final decoded = _decode(response.body);
      if (response.statusCode != 200 || decoded?['user'] is! Map) {
        return _errorFrom(decoded, fallback: 'OTYA user not found.');
      }

      return OtyaIdentityResult(
        value: OtyaPublicIdentity.fromJson(
          Map<String, dynamic>.from(decoded!['user'] as Map),
        ),
      );
    } catch (_) {
      return const OtyaIdentityResult(
        error: 'Could not reach OTYA right now.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  Future<void> clearCachedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUsernameKey);
  }

  Future<void> _cache(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    if (username == null || username.isEmpty) {
      await prefs.remove(_cachedUsernameKey);
    } else {
      await prefs.setString(_cachedUsernameKey, username);
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static OtyaIdentityResult<OtyaPublicIdentity> _errorFrom(
    Map<String, dynamic>? decoded, {
    required String fallback,
  }) {
    final error = decoded?['error'];
    final code = decoded?['code'];
    final available = decoded?['available_at'];
    return OtyaIdentityResult(
      error: error is String && error.trim().isNotEmpty ? error : fallback,
      code: code is String ? code : null,
      availableAt: available is String ? DateTime.tryParse(available) : null,
    );
  }
}
