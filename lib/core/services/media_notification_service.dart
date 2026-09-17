import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'album_art_service.dart';
import 'notification_service.dart';
import 'audio_handler.dart';

/// Owns system Now Playing metadata for notification shade, lock screen,
/// Bluetooth/headset controls and Android media surfaces.
///
/// Android media sessions publish Now Playing independently, but Android 13+
/// notification consent is requested from the first user-initiated playback so
/// the notification shade and lock screen can show the session reliably.
class MediaNotificationService {
  MediaNotificationService._();
  static final MediaNotificationService instance = MediaNotificationService._();

  static const int _maxArtworkBytes = 5 * 1024 * 1024;
  static const int _maxCachedArtworkFiles = 24;

  bool _initialized = false;
  String? _lastArtworkKey;
  Uri? _lastArtworkUri;
  int _metadataGeneration = 0;

  // Audio is the long-lived fallback owner. Temporary surfaces such as the
  // video player register on top of it and automatically reveal the previous
  // owner again when they leave. This prevents an old screen's dispose() from
  // stealing lock-screen Previous/Next from the player that replaced it.
  VoidCallback? _legacySkipPrevious;
  VoidCallback? _legacySkipNext;
  final LinkedHashMap<Object, _TransportCallbacks> _transportOwners =
      LinkedHashMap<Object, _TransportCallbacks>.identity();

  VoidCallback? get onSkipPrevious => _transportOwners.isNotEmpty
      ? _transportOwners.values.last.onSkipPrevious
      : _legacySkipPrevious;

  set onSkipPrevious(VoidCallback? callback) =>
      _legacySkipPrevious = callback;

  VoidCallback? get onSkipNext => _transportOwners.isNotEmpty
      ? _transportOwners.values.last.onSkipNext
      : _legacySkipNext;

  set onSkipNext(VoidCallback? callback) => _legacySkipNext = callback;

  void registerTransportCallbacks(
    Object owner, {
    required VoidCallback onSkipPrevious,
    required VoidCallback onSkipNext,
  }) {
    _transportOwners.remove(owner);
    _transportOwners[owner] = _TransportCallbacks(
      onSkipPrevious: onSkipPrevious,
      onSkipNext: onSkipNext,
    );
  }

  void unregisterTransportCallbacks(Object owner) {
    _transportOwners.remove(owner);
  }

  Future<void> init() async {
    if (_initialized) return;
    // MediaSession must remain available if ordinary notification setup fails.
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

  Future<void> _pruneArtworkCache(Directory dir, {String? keepPath}) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && !entity.path.endsWith('.part')) files.add(entity);
      }
      if (files.length <= _maxCachedArtworkFiles) return;

      final dated = <({File file, DateTime modified})>[];
      for (final file in files) {
        try {
          dated.add((file: file, modified: await file.lastModified()));
        } catch (_) {}
      }
      dated.sort((a, b) => a.modified.compareTo(b.modified));
      var remaining = files.length;
      for (final entry in dated) {
        if (remaining <= _maxCachedArtworkFiles) break;
        if (entry.file.path == keepPath) continue;
        try {
          await entry.file.delete();
          remaining--;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MediaNotification] artwork cache prune skipped: $e');
    }
  }

  Future<Uri?> _cacheRemoteArtwork(Uri uri, String id) async {
    final key = '$id|$uri';
    if (_lastArtworkKey == key && _lastArtworkUri != null) {
      return _lastArtworkUri;
    }

    final client = http.Client();
    // Bound the complete transfer, including a server that sends tiny chunks
    // often enough to avoid the stream inactivity timeout.
    final deadline = Timer(const Duration(seconds: 12), client.close);
    File? part;
    try {
      final request = http.Request('GET', uri);
      // Do not let an artwork host redirect a background request to cleartext
      // HTTP or to a destination OTYA did not validate.
      request.followRedirects = false;
      final response =
          await client.send(request).timeout(const Duration(seconds: 6));
      if (response.statusCode != HttpStatus.ok) return null;

      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > _maxArtworkBytes) {
        return null;
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().startsWith('image/')) return null;
      final ext = contentType.toLowerCase().contains('png') ? 'png' : 'jpg';
      final dir = await _artworkDir();
      final target = File('${dir.path}/now_playing_${id.hashCode}.$ext');
      part = File('${target.path}.part');
      if (await part.exists()) await part.delete();

      final sink = part.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 6))) {
          received += chunk.length;
          if (received > _maxArtworkBytes) {
            throw const _ArtworkTooLargeException();
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0) return null;

      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      part = null;
      final artUri = Uri.file(target.path);
      _lastArtworkKey = key;
      _lastArtworkUri = artUri;
      await _pruneArtworkCache(dir, keepPath: target.path);
      return artUri;
    } on _ArtworkTooLargeException {
      debugPrint('[MediaNotification] remote artwork exceeded safe size limit.');
      return null;
    } catch (e) {
      debugPrint('[MediaNotification] remote artwork unavailable: $e');
      return null;
    } finally {
      deadline.cancel();
      client.close();
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
    }
  }

  Future<Uri?> _stableArtUri(String? albumArtPath, String id) async {
    if (albumArtPath == null || albumArtPath.isEmpty) return null;
    final resolved = await AlbumArtService.instance.resolve(albumArtPath);
    if (resolved == null || resolved.isEmpty) return null;

    final parsed = Uri.tryParse(resolved);
    if (parsed != null && parsed.scheme == 'https') {
      return _cacheRemoteArtwork(parsed, id);
    }
    if (parsed != null && parsed.hasScheme) return null;

    final source = File(resolved);
    if (!await source.exists()) return null;
    try {
      if (await source.length() > _maxArtworkBytes) return null;
    } catch (_) {
      return null;
    }

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
      await _pruneArtworkCache(dir, keepPath: target.path);
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

  Uri? _cachedArtworkFor(String id) {
    final key = _lastArtworkKey;
    if (key == null || !key.startsWith('$id|')) return null;
    return _lastArtworkUri;
  }

  void _publishNowPlaying({
    required String id,
    required String title,
    required String artist,
    required bool isPlaying,
    Uri? artUri,
  }) {
    AudioHandlerSingleton.instance.setMediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: artUri,
    );
    AudioHandlerSingleton.instance.setPlaying(isPlaying);
  }

  Future<void> show({
    required String id,
    required String title,
    required String artist,
    required bool isPlaying,
    String? albumArtPath,
  }) async {
    // This runs only after the person starts playback. Asking here, instead of
    // behind startup dialogs, lets Android show the real Now Playing surface
    // and lock-screen controls on Android 13+ without interrupting onboarding.
    unawaited(NotificationService.instance.requestPermissionOnce());
    final generation = ++_metadataGeneration;

    // Publish title/artist/play state synchronously before the first await.
    // The player stream calls show() as playback starts, so this guarantees the
    // MediaItem exists before another listener can promote the Android
    // foreground media service with playing=true. If AudioService is still
    // recovering, AudioHandlerSingleton queues this exact state and flushes it
    // metadata-first when the handler becomes ready.
    _publishNowPlaying(
      id: id,
      title: title,
      artist: artist,
      isPlaying: isPlaying,
      artUri: _cachedArtworkFor(id),
    );

    if (!_initialized) await init();
    await _ensureMediaSession();
    if (generation != _metadataGeneration) return;

    // Republish after recovery in case the initial synchronous write was queued.
    // Artwork is deliberately not required for the core media notification.
    _publishNowPlaying(
      id: id,
      title: title,
      artist: artist,
      isPlaying: isPlaying,
      artUri: _cachedArtworkFor(id),
    );

    final artUri = await _stableArtUri(albumArtPath, id);
    if (generation != _metadataGeneration || artUri == null) return;

    // Artwork is a progressive enhancement. Do not write the old isPlaying
    // value again here because playback may have changed while artwork loaded;
    // the player stream remains authoritative for current play/pause state.
    AudioHandlerSingleton.instance.setMediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: artUri,
    );
  }

  Future<void> showWithBitmap({
    required String id,
    required String title,
    required String artist,
    required bool isPlaying,
    required Uint8List albumArtBytes,
  }) async {
    unawaited(NotificationService.instance.requestPermissionOnce());
    final generation = ++_metadataGeneration;

    // Bitmap artwork must never gate the core MediaSession either. Publish the
    // textual metadata synchronously, then recover/init and add artwork later.
    _publishNowPlaying(
      id: id,
      title: title,
      artist: artist,
      isPlaying: isPlaying,
      artUri: _cachedArtworkFor(id),
    );

    if (!_initialized) await init();
    await _ensureMediaSession();
    if (generation != _metadataGeneration) return;

    _publishNowPlaying(
      id: id,
      title: title,
      artist: artist,
      isPlaying: isPlaying,
      artUri: _cachedArtworkFor(id),
    );

    if (albumArtBytes.isEmpty || albumArtBytes.length > _maxArtworkBytes) return;

    Uri? artUri;
    try {
      final dir = await _artworkDir();
      final file = File('${dir.path}/now_playing_${id.hashCode}.jpg');
      await file.writeAsBytes(albumArtBytes, flush: true);
      artUri = Uri.file(file.path);
      _lastArtworkKey = '$id|bitmap';
      _lastArtworkUri = artUri;
      await _pruneArtworkCache(dir, keepPath: file.path);
    } catch (e) {
      debugPrint('[MediaNotification] bitmap cache failed: $e');
    }
    if (generation != _metadataGeneration || artUri == null) return;
    AudioHandlerSingleton.instance.setMediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: artUri,
    );
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

class _TransportCallbacks {
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;

  const _TransportCallbacks({
    required this.onSkipPrevious,
    required this.onSkipNext,
  });
}

class _ArtworkTooLargeException implements Exception {
  const _ArtworkTooLargeException();
}
