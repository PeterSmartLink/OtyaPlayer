import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'media_notification_service.dart';
import 'audio_session_service.dart';

/// Bridges media_kit's [Player] to Android's MediaSession/foreground service.
class OtyaAudioHandler extends BaseAudioHandler with SeekHandler {
  Player? _player;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  void attachPlayer(Player player) {
    debugPrint('[OtyaAudioHandler] Attaching player');
    _cancelSubscriptions();
    _player = player;
    _subscribeToPlayer(player);
    _updatePlaybackState();
    debugPrint('[OtyaAudioHandler] Player attached.');
  }

  void detachPlayer({bool disposePlayer = false}) {
    debugPrint('[OtyaAudioHandler] Detaching player');
    _cancelSubscriptions();
    final player = _player;
    _player = null;
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    if (disposePlayer && player != null) {
      try {
        player.dispose();
      } catch (e) {
        debugPrint('[OtyaAudioHandler] Player dispose error: $e');
      }
    }
  }

  void _subscribeToPlayer(Player player) {
    _playingSub = player.stream.playing.listen(
      (playing) => _updatePlaybackState(playing: playing),
    );
    _bufferingSub = player.stream.buffering.listen(
      (buffering) => _updatePlaybackState(buffering: buffering),
    );
    _positionSub = player.stream.position.listen(
      (position) => _updatePlaybackState(position: position),
    );
    _durationSub = player.stream.duration.listen((duration) {
      final current = mediaItem.value;
      if (current != null && duration != Duration.zero) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  void _cancelSubscriptions() {
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub = _bufferingSub = _positionSub = _durationSub = null;
  }

  List<MediaControl> _controls(bool isPlaying) => [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.rewind,
        MediaControl.fastForward,
      ];

  void _updatePlaybackState({
    bool? playing,
    bool? buffering,
    Duration? position,
  }) {
    final p = _player;
    if (p == null) return;
    final isPlaying = playing ?? p.state.playing;
    final isBuffering = buffering ?? p.state.buffering;
    final pos = position ?? p.state.position;
    final processingState = (isBuffering && p.state.duration == Duration.zero)
        ? AudioProcessingState.loading
        : isBuffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready;

    playbackState.add(playbackState.value.copyWith(
      controls: _controls(isPlaying),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: isPlaying,
      updatePosition: pos,
      bufferedPosition: p.state.buffer,
      speed: p.state.rate,
      queueIndex: null,
    ));
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  void updateMediaItemFromParts({
    required String id,
    required String title,
    required String artist,
    Uri? artUri,
    Duration? duration,
  }) {
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: 'Otya',
      artUri: artUri,
      duration: duration ?? _player?.state.duration,
    ));
  }

  @override
  Future<void> play() async {
    if (_player == null) return;
    await AudioSessionService.instance.activate();
    await _player!.play();
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> stop() async {
    await _player?.pause();
    detachPlayer();
    await AudioSessionService.instance.deactivate();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> rewind() async {
    final p = _player;
    if (p == null) return;
    final target = p.state.position - const Duration(seconds: 10);
    await p.seek(target.isNegative ? Duration.zero : target);
  }

  @override
  Future<void> fastForward() async {
    final p = _player;
    if (p == null) return;
    final target = p.state.position + const Duration(seconds: 10);
    final duration = p.state.duration;
    await p.seek(duration > Duration.zero && target > duration ? duration : target);
  }

  @override
  Future<void> skipToNext() async {
    MediaNotificationService.instance.onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    MediaNotificationService.instance.onSkipPrevious?.call();
  }

  @override
  Future<void> onTaskRemoved() async {
    debugPrint('[OtyaAudioHandler] App task removed; keeping media session alive.');
  }

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
    await super.onNotificationDeleted();
  }
}

class AudioHandlerSingleton {
  AudioHandlerSingleton._();
  static final AudioHandlerSingleton instance = AudioHandlerSingleton._();

  OtyaAudioHandler? _handler;
  Player? _pendingPlayer;
  MediaItem? _pendingMediaItem;
  bool? _pendingPlaying;
  Future<void> Function()? _ensureReadyCallback;
  Future<void>? _ensureReadyFuture;

  OtyaAudioHandler? get handler => _handler;
  bool get isReady => _handler != null;

  /// Registers the process-level AudioService initializer. Media notification
  /// calls can use this to recover if Android service initialization failed
  /// during startup. Concurrent recovery attempts share one in-flight future.
  void configureEnsureReady(Future<void> Function() callback) {
    _ensureReadyCallback = callback;
  }

  Future<bool> ensureReady() async {
    if (_handler != null) return true;
    final callback = _ensureReadyCallback;
    if (callback == null) return false;

    final inFlight = _ensureReadyFuture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // The owning initializer reports failures. A later call may retry.
      }
      return _handler != null;
    }

    final attempt = Future<void>.sync(callback);
    _ensureReadyFuture = attempt;
    try {
      await attempt;
    } catch (error) {
      debugPrint('[AudioHandlerSingleton] Media-session recovery failed: $error');
    } finally {
      if (identical(_ensureReadyFuture, attempt)) {
        _ensureReadyFuture = null;
      }
    }
    return _handler != null;
  }

  List<MediaControl> _controls(bool isPlaying) => [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.rewind,
        MediaControl.fastForward,
      ];

  set handler(OtyaAudioHandler? h) {
    _handler = h;
    if (h == null) return;

    final pendingPlayer = _pendingPlayer;
    if (pendingPlayer != null) {
      _pendingPlayer = null;
      h.attachPlayer(pendingPlayer);
    }

    final pendingItem = _pendingMediaItem;
    if (pendingItem != null) {
      _pendingMediaItem = null;
      h.mediaItem.add(
        pendingItem.copyWith(
          duration: pendingItem.duration ?? pendingPlayer?.state.duration,
        ),
      );
    }

    final pendingPlaying = _pendingPlaying;
    if (pendingPlaying != null) {
      _pendingPlaying = null;
      final current = h.playbackState.value;
      h.playbackState.add(current.copyWith(
        playing: pendingPlaying,
        controls: _controls(pendingPlaying),
        androidCompactActionIndices: const [0, 1, 2],
      ));
    }
    debugPrint('[AudioHandlerSingleton] Handler ready; queued Now Playing state flushed.');
  }

  void attachPlayer(Player player) {
    final h = _handler;
    if (h == null) {
      _pendingPlayer = player;
      debugPrint('[AudioHandlerSingleton] Queued player until audio handler is ready.');
      return;
    }
    h.attachPlayer(player);
  }

  void setMediaItem({
    required String id,
    required String title,
    required String artist,
    Uri? artUri,
    Duration? duration,
  }) {
    final h = _handler;
    if (h != null) {
      h.updateMediaItemFromParts(
        id: id,
        title: title,
        artist: artist,
        artUri: artUri,
        duration: duration,
      );
      return;
    }
    _pendingMediaItem = MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: 'Otya',
      artUri: artUri,
      duration: duration,
    );
    debugPrint('[AudioHandlerSingleton] Queued Now Playing metadata until handler is ready.');
  }

  void setPlaying(bool isPlaying) {
    final h = _handler;
    if (h == null) {
      _pendingPlaying = isPlaying;
      return;
    }
    final current = h.playbackState.value;
    h.playbackState.add(current.copyWith(
      playing: isPlaying,
      controls: _controls(isPlaying),
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  void clearMediaItem() {
    _pendingMediaItem = null;
    _pendingPlaying = false;
    final h = _handler;
    if (h == null) return;
    h.mediaItem.add(null);
    h.playbackState.add(h.playbackState.value.copyWith(
      playing: false,
      controls: const [],
    ));
  }

  void detachPlayer({bool disposePlayer = false}) {
    _pendingPlayer = null;
    _pendingPlaying = false;
    _handler?.detachPlayer(disposePlayer: disposePlayer);
  }
}
