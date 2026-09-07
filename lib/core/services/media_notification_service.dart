import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'album_art_service.dart';
import 'audio_handler.dart';
import 'shared_notification_plugin.dart';

/// Owns system Now Playing metadata for notification shade, lock screen,
/// Bluetooth/headset controls and Android media surfaces.
///
/// Android media-session notifications are separate from ordinary Otya
/// notification consent. More importantly, Now Playing must be able to recover
/// if Android's foreground media service was not ready during app bootstrap.
class MediaNotificationService {
  MediaNotificationService._();
  static final MediaNotificationService instance = MediaNotificationService._();

  bool _initialized = false;
  String? _lastArtworkKey;
  Uri? _lastArtworkUri;
  int _metadataGeneration = 0;

  void Function()? onSkipPrevious;
  void Function()? onSkipNext;

  Future<void> init() async {
    if (_initialized) return;
    await initSharedNotificationsPlugin();
    // A startup AudioService failure must not become permanent. The registered
    // initializer is idempotent and coalesces concurrent attempts.
    await AudioHandlerSingleton.instance.ensureReady();
    _initialized = true;
    debugPrint('[MediaNotificationService] Initialized.');
  }

  Future<Directory> _artworkDir() async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory('${cache.path}/now_playing_art');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Uri?> _cacheRemoteArtwork(Uri uri, String id) async {
    final key = '$id|$uri';
    if (_lastArtworkKey == key && _lastArtworkUri != null) {
      return _lastArtworkUri;
    }
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      if (response.bodyBytes.length > 5 * 1024 * 1024) return null;
      final contentType = response.headers['content-type'] ?? '';
      final ext = contentType.contains('png') ? 'png' : 'jpg';
      final dir = await _artworkDir();
      final target = File('${dir.path}/now_playing_${id.hashCode}.$ext');
      await target.writeAsBytes(response.bodyBytes, flush: true);
      final artUri = Uri.file(target.path);
      _lastArtworkKey = key;
      _lastArtworkUri = artUri;
      return artUri;
    } catch (e) {
      debugPrint('[MediaNotification] remote artwork unavailable: $e');
      return null;
    }
  }

  Future<Uri?> _stableArtUri(String? albumArtPath, String id) async {
    if (albumArtPath == null || albumArtPath.isEmpty) return null;
    final resolved = await AlbumArtService.instance.resolve(albumArtPath);
    if (resolved == null || resolved.isEmpty) return null;

    final parsed = Uri.tryParse(resolved);
    if (parsed != null && (parsed.scheme == 'https' || parsed.scheme == 'http')) {
      return _cacheRemoteArtwork(parsed, id);
    }

    final source = File(resolved);
    if (!await source.exists()) return null;

    final key = '$id|$resolved';
    if (_lastArtworkKey == key && _lastArtworkUri != null) {
      return _lastArtworkUri;
    }

    try {
      final dir = await _artworkDir();
      final ext = resolved.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final target = File('${dir.path}/now_playing_${id.hashCode}.$ext');
      await source.copy(target.path);
      final uri = Uri.file(target.path);
      _lastArtworkKey = key;
      _lastArtworkUri = uri;
      return uri;
    } catch (e) {
      debugPrint('[MediaNotification] artwork cache failed: $e');
      return Uri.file(source.path);
    }
  }

  Future<void> _ensureMediaSession() async {
    final ready = await AudioHandlerSingleton.instance.ensureReady();
    if (!ready) {
      debugPrint(
        '[MediaNotification] Android media session is not ready; state is queued for recovery.',
      );
    }
  }

  Future<void> show({
    required String id,
    required String title,
    required String artist,
    required bool isPlaying,
    String? albumArtPath,
  }) async {
    final generation = ++_metadataGeneration;
    if (!_initialized) await init();
    await _ensureMediaSession();
    final artUri = await _stableArtUri(albumArtPath, id);
    if (generation != _metadataGeneration) return;
    AudioHandlerSingleton.instance.setMediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: artUri,
    );
    AudioHandlerSingleton.instance.setPlaying(isPlaying);
  }

  Future<void> showWithBitmap({
    required String id,
    required String title,
    required String artist,
    required bool isPlaying,
    required Uint8List albumArtBytes,
  }) async {
    final generation = ++_metadataGeneration;
    if (!_initialized) await init();
    await _ensureMediaSession();
    Uri? artUri;
    try {
      final dir = await _artworkDir();
      final file = File('${dir.path}/now_playing_${id.hashCode}.jpg');
      await file.writeAsBytes(albumArtBytes, flush: true);
      artUri = Uri.file(file.path);
      _lastArtworkKey = '$id|bitmap';
      _lastArtworkUri = artUri;
    } catch (e) {
      debugPrint('[MediaNotification] bitmap cache failed: $e');
    }
    if (generation != _metadataGeneration) return;
    AudioHandlerSingleton.instance.setMediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: artUri,
    );
    AudioHandlerSingleton.instance.setPlaying(isPlaying);
  }

  Future<void> updatePlayState(bool isPlaying) async {
    await _ensureMediaSession();
    AudioHandlerSingleton.instance.setPlaying(isPlaying);
  }

  Future<void> dismiss() async {
    ++_metadataGeneration;
    _lastArtworkKey = null;
    _lastArtworkUri = null;
    AudioHandlerSingleton.instance.clearMediaItem();
  }
}
