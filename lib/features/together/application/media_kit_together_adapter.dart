import 'package:media_kit/media_kit.dart';

import 'playback_sync_engine.dart';

/// Thin bridge between OTYA Together and the media_kit engine OTYA already uses.
///
/// It does not own or initialize a Player. Normal local playback keeps its
/// existing lifecycle; Together attaches to that same Player only while a room
/// is active.
class MediaKitTogetherAdapter {
  final Player player;
  final PlaybackSyncEngine syncEngine;
  final Stopwatch monotonicClock;

  int _nextSequence = 0;
  bool _applyingRemote = false;

  MediaKitTogetherAdapter({
    required this.player,
    PlaybackSyncEngine? syncEngine,
    Stopwatch? monotonicClock,
  })  : syncEngine = syncEngine ?? PlaybackSyncEngine(),
        monotonicClock = monotonicClock ?? (Stopwatch()..start());

  bool get applyingRemote => _applyingRemote;

  TogetherPlaybackState captureHostState({required int mediaRevision}) {
    final state = player.state;
    return TogetherPlaybackState(
      sequence: _nextSequence++,
      mediaRevision: mediaRevision,
      playing: state.playing,
      positionMs: state.position.inMilliseconds,
      sentMonotonicUs: monotonicClock.elapsedMicroseconds,
      rate: state.rate > 0 ? state.rate : 1.0,
    );
  }

  void resetForMediaRevision(int revision) {
    _nextSequence = 0;
    syncEngine.resetForMediaRevision(revision);
  }

  void addClockSample(TogetherClockSample sample) {
    syncEngine.addClockSample(sample);
  }

  /// Applies a fresh host state and returns false when it was stale or belonged
  /// to another media revision.
  Future<bool> applyRemoteState(TogetherPlaybackState remote) async {
    final current = player.state;
    final correction = syncEngine.accept(
      remote: remote,
      localNowUs: monotonicClock.elapsedMicroseconds,
      currentPositionMs: current.position.inMilliseconds,
      currentPlaying: current.playing,
    );
    if (correction == null) return false;

    _applyingRemote = true;
    try {
      if (correction.requiresSeek) {
        await player.seek(Duration(milliseconds: correction.expectedPositionMs));
      }

      final currentRate = player.state.rate;
      if ((currentRate - correction.playbackSpeed).abs() > 0.001) {
        await player.setRate(correction.playbackSpeed);
      }

      final nowPlaying = player.state.playing;
      if (correction.shouldPlay && !nowPlaying) {
        await player.play();
      } else if (!correction.shouldPlay && nowPlaying) {
        await player.pause();
      }
      return true;
    } finally {
      _applyingRemote = false;
    }
  }
}
