import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_coordinator.dart';

/// Owns Otya's app-wide audio focus and interruption policy.
///
/// Android exposes one shared audio-focus contract for the app. Keeping the
/// policy here prevents the MediaKit player, background audio service and
/// platform bridge from competing over focus independently.
class AudioSessionService {
  AudioSessionService._();
  static final AudioSessionService instance = AudioSessionService._();

  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  Future<void>? _initialization;
  bool _initialized = false;
  bool _pauseDuringCalls = true;
  bool _resumeAfterInterruption = false;
  Player? _playerPausedForInterruption;
  Player? _duckedPlayer;
  double? _volumeBeforeDuck;

  Future<void> init({required bool pauseDuringCalls}) async {
    // Startup calls can arrive from the first-frame bootstrap and from the
    // first MediaSession command at nearly the same time. Keep a single
    // initialization flight so neither path installs competing interruption
    // listeners or leaves Android focus configured only half-way through.
    final inFlight = _initialization;
    if (inFlight != null) {
      await inFlight;
      await setPauseDuringCalls(pauseDuringCalls);
      return;
    }

    if (!_initialized) {
      final attempt = _configureSession();
      _initialization = attempt;
      try {
        await attempt;
      } finally {
        if (identical(_initialization, attempt)) _initialization = null;
      }
    }

    await setPauseDuringCalls(pauseDuringCalls);
    debugPrint(
      '[AudioSession] configured; pauseDuringCalls=$_pauseDuringCalls.',
    );
  }

  Future<void> _configureSession() async {
    if (!_initialized) {
      final session = await AudioSession.instance;
      _session = session;
      await session.configure(AudioSessionConfiguration.music());

      // Output becoming noisy (wired/Bluetooth audio disappears) is always
      // handled. This avoids suddenly routing active playback to the speaker.
      _noisySub = session.becomingNoisyEventStream.listen(
        (_) => unawaited(_pauseForNoisyOutput()),
        onError: (Object error, StackTrace stack) {
          debugPrint('[AudioSession] noisy stream error: $error');
        },
      );
      _initialized = true;
    }
  }

  Future<void> setPauseDuringCalls(bool enabled) async {
    _pauseDuringCalls = enabled;
    if (!_initialized) {
      await init(pauseDuringCalls: enabled);
      return;
    }

    if (enabled) {
      if (_interruptionSub != null) return;
      final session = _session ?? await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen(
        _handleInterruption,
        onError: (Object error, StackTrace stack) {
          debugPrint('[AudioSession] interruption stream error: $error');
        },
      );
      return;
    }

    await _interruptionSub?.cancel();
    _interruptionSub = null;
    _resumeAfterInterruption = false;
    _playerPausedForInterruption = null;

    final previous = _volumeBeforeDuck;
    final duckedPlayer = _duckedPlayer;
    _volumeBeforeDuck = null;
    _duckedPlayer = null;
    if (previous != null &&
        duckedPlayer != null &&
        identical(PlaybackCoordinator.instance.activePlayer, duckedPlayer)) {
      try {
        await duckedPlayer.setVolume(previous);
      } catch (error) {
        debugPrint('[AudioSession] volume restore failed: $error');
      }
    }
  }

  /// Claims platform audio focus immediately before user-initiated playback.
  ///
  /// MediaKit can start audio without this explicit handshake on many devices,
  /// but doing so is unreliable after calls, Bluetooth route changes, or after
  /// Android has removed and recreated the media notification.
  Future<bool> activate() async {
    // The UI bootstrap intentionally defers secondary work until after the
    // first frame. A lock-screen/Bluetooth command or a very fast first tap
    // can therefore reach this method before that work. Configure the same
    // music policy here instead of activating Android's default session.
    if (!_initialized) {
      try {
        await init(pauseDuringCalls: _pauseDuringCalls);
      } catch (error) {
        debugPrint('[AudioSession] initial configuration failed: $error');
        return false;
      }
    }
    final session = _session ?? await AudioSession.instance;
    _session = session;
    try {
      return await session.setActive(true);
    } catch (error) {
      debugPrint('[AudioSession] focus activation failed: $error');
      return false;
    }
  }

  Future<void> deactivate() async {
    final session = _session;
    if (session == null) return;
    try {
      await session.setActive(false);
    } catch (error) {
      debugPrint('[AudioSession] focus release failed: $error');
    }
  }

  void _handleInterruption(AudioInterruptionEvent event) {
    if (!_pauseDuringCalls) return;
    final player = PlaybackCoordinator.instance.activePlayer;
    if (player == null) return;

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // Remember both the volume and the exact player. A different media
          // owner may become active before Android ends the interruption.
          if (_duckedPlayer == null) {
            _duckedPlayer = player;
            _volumeBeforeDuck = player.state.volume;
          }
          unawaited(
            player.setVolume(
              (player.state.volume * .35).clamp(0.0, 100.0),
            ),
          );
          break;
        case AudioInterruptionType.pause:
          _resumeAfterInterruption = player.state.playing;
          _playerPausedForInterruption =
              _resumeAfterInterruption ? player : null;
          if (_resumeAfterInterruption) unawaited(player.pause());
          break;
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = false;
          _playerPausedForInterruption = null;
          if (player.state.playing) unawaited(player.pause());
          break;
      }
      return;
    }

    switch (event.type) {
      case AudioInterruptionType.duck:
        final previous = _volumeBeforeDuck;
        final duckedPlayer = _duckedPlayer;
        _volumeBeforeDuck = null;
        _duckedPlayer = null;
        if (previous != null &&
            duckedPlayer != null &&
            identical(PlaybackCoordinator.instance.activePlayer, duckedPlayer)) {
          unawaited(duckedPlayer.setVolume(previous));
        }
        break;
      case AudioInterruptionType.pause:
        final shouldResume = _resumeAfterInterruption;
        final interruptedPlayer = _playerPausedForInterruption;
        _resumeAfterInterruption = false;
        _playerPausedForInterruption = null;
        if (shouldResume && interruptedPlayer != null) {
          unawaited(_resumeAfterFocusInterruption(interruptedPlayer));
        }
        break;
      case AudioInterruptionType.unknown:
        _resumeAfterInterruption = false;
        _playerPausedForInterruption = null;
        break;
    }
  }

  Future<void> _resumeAfterFocusInterruption(Player player) async {
    // Android may have fully revoked audio focus during a call or competing
    // media session. Reclaim it before asking MediaKit to resume; otherwise
    // some devices report playing while audio remains silent or immediately
    // pause the session again.
    final focusGranted = await activate();
    if (!focusGranted) {
      debugPrint('[AudioSession] resume skipped because audio focus was not restored.');
      return;
    }
    // The active playback owner may have changed while the interruption was
    // ending. Never resume an old player behind the current screen/session.
    if (!identical(PlaybackCoordinator.instance.activePlayer, player)) return;
    try {
      await player.play();
    } catch (error) {
      debugPrint('[AudioSession] resume after interruption failed: $error');
    }
  }

  Future<void> _pauseForNoisyOutput() async {
    final player = PlaybackCoordinator.instance.activePlayer;
    if (player == null || !player.state.playing) return;
    _resumeAfterInterruption = false;
    _playerPausedForInterruption = null;
    await player.pause();
    debugPrint('[AudioSession] paused after audio output became noisy.');
  }

  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    _interruptionSub = null;
    _noisySub = null;
    _playerPausedForInterruption = null;
    _duckedPlayer = null;
    _volumeBeforeDuck = null;
    _session = null;
    _initialization = null;
    _initialized = false;
  }
}
