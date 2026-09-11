// lib/core/services/backup_service.dart
//
// Handles Drive backup via Auth Worker endpoints.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../database/otya_database.dart';
import '../models/playlist.dart';
import 'auth_service.dart';
import 'http_client.dart';
import '../config/environment.dart';

const _kAuthBase = Environment.authUrl;
const _kBackupSchemaVersion = 1;
const _kBackupPayloadType = 'otya_recovery_snapshot';
const _kMaxPlaylists = 5000;
const _kMaxMediaIdsPerPlaylist = 50000;
const _kMaxPlaylistNameLength = 240;

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  http.Client get _client => AppHttpClient.instance.client;
  static const Duration _timeout = Duration(seconds: 30);

  String _errorMessage(http.Response res, String fallback) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) return error;
      }
    } catch (_) {}
    return '$fallback (${res.statusCode})';
  }

  Map<String, dynamic> _decodeObject(http.Response res, String fallback) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw Exception(fallback);
  }

  Future<void> backup(Map<String, dynamic> data, String driveAccessToken) async {
    final token = await AuthService.instance.getValidToken();
    if (token == null) throw Exception('Please sign in to Otya first.');
    final res = await _client.post(
      Uri.parse('$_kAuthBase/backup'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'drive_token': driveAccessToken, 'data': data}),
    ).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Backup failed'));
    }
  }

  Future<Map<String, dynamic>?> restore(String driveAccessToken) async {
    final token = await AuthService.instance.getValidToken();
    if (token == null) throw Exception('Please sign in to Otya first.');
    final uri = Uri.parse('$_kAuthBase/backup');
    final res = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'X-Otya-Drive-Token': driveAccessToken,
      },
    ).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Restore failed'));
    }
    final body = _decodeObject(res, 'The backup response was not valid.');
    final data = body['data'];
    if (data == null) return null;
    if (data is! Map<String, dynamic>) {
      throw Exception('The Drive backup has an unsupported format.');
    }
    return data;
  }

  Future<void> deleteBackup(String driveAccessToken) async {
    final token = await AuthService.instance.getValidToken();
    if (token == null) throw Exception('Please sign in to Otya first.');
    final res = await _client.delete(
      Uri.parse('$_kAuthBase/backup'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'drive_token': driveAccessToken}),
    ).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Delete failed'));
    }
  }

  Future<Map<String, dynamic>> buildBackupData() async {
    final playlists = OtyaDatabase.instance.getAllPlaylists()
        .map((p) => {
              'id': p.id,
              'name': p.name,
              'mediaIds': p.mediaIds,
              'createdAt': p.createdAt.toIso8601String(),
              'updatedAt': p.updatedAt.toIso8601String(),
            })
        .toList();

    return {
      'schema_version': _kBackupSchemaVersion,
      'payload_type': _kBackupPayloadType,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'playlists': playlists,
      'eq_presets': <dynamic>[],
      'bookmarks': <dynamic>[],
    };
  }

  List<Playlist> _parsePlaylists(Map<String, dynamic> data) {
    final schemaVersion = data['schema_version'] ?? data['version'];
    if (schemaVersion is! int || schemaVersion != _kBackupSchemaVersion) {
      throw Exception('This backup version is not supported by this OTYA build.');
    }
    if (data['payload_type'] != _kBackupPayloadType) {
      throw Exception('This is not an OTYA recovery snapshot.');
    }

    final rawPlaylists = data['playlists'];
    if (rawPlaylists != null && rawPlaylists is! List) {
      throw Exception('The Drive backup is damaged or incomplete.');
    }

    final rows = rawPlaylists as List<dynamic>? ?? const [];
    if (rows.length > _kMaxPlaylists) {
      throw Exception('The Drive backup contains too many playlists.');
    }

    final parsed = <Playlist>[];
    for (final raw in rows) {
      if (raw is! Map<String, dynamic>) {
        throw Exception('The Drive backup contains an invalid playlist.');
      }

      final id = raw['id'];
      final name = raw['name'];
      final rawMediaIds = raw['mediaIds'];
      if (id is! String || id.trim().isEmpty || id.length > 240) {
        throw Exception('The Drive backup contains an invalid playlist ID.');
      }
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > _kMaxPlaylistNameLength) {
        throw Exception('The Drive backup contains an invalid playlist name.');
      }
      if (rawMediaIds != null && rawMediaIds is! List) {
        throw Exception('The Drive backup contains invalid playlist media.');
      }

      final mediaRows = rawMediaIds as List<dynamic>? ?? const [];
      if (mediaRows.length > _kMaxMediaIdsPerPlaylist) {
        throw Exception('A restored playlist contains too many media items.');
      }
      final mediaIds = <String>[];
      for (final value in mediaRows) {
        if (value is! String || value.isEmpty || value.length > 512) {
          throw Exception('The Drive backup contains an invalid media reference.');
        }
        mediaIds.add(value);
      }

      final createdRaw = raw['createdAt'];
      final updatedRaw = raw['updatedAt'];
      if (createdRaw != null && createdRaw is! String) {
        throw Exception('The Drive backup contains an invalid creation date.');
      }
      if (updatedRaw != null && updatedRaw is! String) {
        throw Exception('The Drive backup contains an invalid update date.');
      }

      final now = DateTime.now();
      parsed.add(
        Playlist(
          id: id,
          name: name,
          mediaIds: mediaIds,
          createdAt: DateTime.tryParse(createdRaw as String? ?? '') ?? now,
          updatedAt: DateTime.tryParse(updatedRaw as String? ?? '') ?? now,
        ),
      );
    }
    return parsed;
  }

  Future<int> restoreFromData(Map<String, dynamic> data) async {
    // Validate the complete snapshot before writing anything. A corrupt row can
    // therefore never leave the user's database in a partially restored state.
    final playlists = _parsePlaylists(data);
    debugPrint('[BackupService] Restoring ${playlists.length} playlists');

    for (final playlist in playlists) {
      await OtyaDatabase.instance.savePlaylist(playlist);
    }
    return playlists.length;
  }
}
