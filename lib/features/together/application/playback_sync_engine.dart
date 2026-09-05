import 'dart:math' as math;

class TogetherPlaybackState {
  final int sequence;
  final int mediaRevision;
  final bool playing;
  final int positionMs;
  final int sentMonotonicUs;
  final double rate;

  const TogetherPlaybackState({
    required this.sequence,
    required this.mediaRevision,
    required this.playing,
    required this.positionMs,
    required this.sentMonotonicUs,
    this.rate = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'seq': sequence,
        'media_revision': mediaRevision,
        'playing': playing,
        'position_ms': positionMs,
        'sent_us': sentMonotonicUs,
        'rate': rate,
      };

  static TogetherPlaybackState? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final sequence = json['seq'];
    final mediaRevision = json['media_revision'];
    final playing = json['playing'];
    final positionMs = json['position_ms'];
    final sentUs = json['sent_us'];
    final rate = json['rate'];
    if (sequence is! int ||
        mediaRevision is! int ||
        playing is! bool ||
        positionMs is! int ||
        sentUs is! int ||
        (rate is! int && rate is! double)) {
      return null;
    }
    final parsedRate = (rate as num).toDouble();
    if (sequence < 0 ||
        mediaRevision < 0 ||
        positionMs < 0 ||
        sentUs < 0 ||
        !parsedRate.isFinite ||
        parsedRate <= 0 ||
        parsedRate > 4) {
      return null;
    }
    return TogetherPlaybackState(
      sequence: sequence,
      mediaRevision: mediaRevision,
      playing: playing,
      positionMs: positionMs,
      sentMonotonicUs: sentUs,
      rate: parsedRate,
    );
  }
}

enum PlaybackCorrectionKind {
  none,
  speed,
  seek,
}

class PlaybackSyncCorrection {
  final PlaybackCorrectionKind kind;
  final bool shouldPlay;
  final int expectedPositionMs;
  final int driftMs;
  final double playbackSpeed;

  const PlaybackSyncCorrection({
    required this.kind,
    required this.shouldPlay,
    required this.expectedPositionMs,
    required this.driftMs,
    required this.playbackSpeed,
  });

  bool get requiresSeek => kind == PlaybackCorrectionKind.seek;
}

class TogetherClockSample {
  /// Guest monotonic timestamp immediately before sending ping.
  final int guestSendUs;

  /// Host monotonic timestamp when it produced the pong payload.
  final int hostReplyUs;

  /// Guest monotonic timestamp immediately after receiving pong.
  final int guestReceiveUs;

  const TogetherClockSample({
    required this.guestSendUs,
    required this.hostReplyUs,
    required this.guestReceiveUs,
  });

  int get roundTripUs => math.max(0, guestReceiveUs - guestSendUs);

  /// Approximate host monotonic clock minus guest monotonic clock.
  int get remoteMinusLocalUs {
    final guestMidpointUs = guestSendUs + (roundTripUs ~/ 2);
    return hostReplyUs - guestMidpointUs;
  }
}

/// Small state-replication engine used by Nearby and Anywhere Together.
///
/// It does not know about Flutter or media_kit. A player adapter applies the
/// returned correction, which keeps network/session behavior testable without
/// risking normal local playback.
class PlaybackSyncEngine {
  static const int softDriftMs = 80;
  static const int hardDriftMs = 250;
  static const double catchUpSpeed = 1.02;
  static const double slowDownSpeed = 0.98;

  int _remoteMinusLocalUs = 0;
  int _lastSequence = -1;
  int _mediaRevision = 0;
  TogetherClockSample? _bestClockSample;

  int get remoteMinusLocalUs => _remoteMinusLocalUs;
  int get lastSequence => _lastSequence;
  int get mediaRevision => _mediaRevision;

  void resetForMediaRevision(int revision) {
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
    _mediaRevision = revision;
    _lastSequence = -1;
  }

  /// Keeps the lowest-RTT sample because asymmetric delay introduces less
  /// uncertainty when the overall network round-trip is small.
  void addClockSample(TogetherClockSample sample) {
    final current = _bestClockSample;
    if (current == null || sample.roundTripUs < current.roundTripUs) {
      _bestClockSample = sample;
      _remoteMinusLocalUs = sample.remoteMinusLocalUs;
    }
  }

  PlaybackSyncCorrection? accept({
    required TogetherPlaybackState remote,
    required int localNowUs,
    required int currentPositionMs,
    required bool currentPlaying,
  }) {
    if (remote.mediaRevision != _mediaRevision) return null;
    if (remote.sequence <= _lastSequence) return null;
    if (localNowUs < 0 || currentPositionMs < 0) return null;

    _lastSequence = remote.sequence;

    final estimatedRemoteNowUs = localNowUs + _remoteMinusLocalUs;
    final elapsedUs = math.max(0, estimatedRemoteNowUs - remote.sentMonotonicUs);
    final elapsedMs = remote.playing
        ? ((elapsedUs / 1000.0) * remote.rate).round()
        : 0;
    final expected = math.max(0, remote.positionMs + elapsedMs);

    // Positive drift means this guest is ahead of the host; negative drift
    // means it is behind.
    final drift = currentPositionMs - expected;
    final magnitude = drift.abs();

    if (magnitude > hardDriftMs) {
      return PlaybackSyncCorrection(
        kind: PlaybackCorrectionKind.seek,
        shouldPlay: remote.playing,
        expectedPositionMs: expected,
        driftMs: drift,
        playbackSpeed: remote.rate,
      );
    }

    if (remote.playing && magnitude > softDriftMs) {
      final correction = drift > 0 ? slowDownSpeed : catchUpSpeed;
      return PlaybackSyncCorrection(
        kind: PlaybackCorrectionKind.speed,
        shouldPlay: true,
        expectedPositionMs: expected,
        driftMs: drift,
        playbackSpeed: (remote.rate * correction).clamp(0.25, 4.0).toDouble(),
      );
    }

    // Even with negligible position drift, play/pause is authoritative. The
    // adapter compares shouldPlay with its local state and acts only if needed.
    // Reading currentPlaying here documents that local state is intentionally
    // not used to reject an otherwise fresh authoritative packet.
    final _ = currentPlaying;
    return PlaybackSyncCorrection(
      kind: PlaybackCorrectionKind.none,
      shouldPlay: remote.playing,
      expectedPositionMs: expected,
      driftMs: drift,
      playbackSpeed: remote.rate,
    );
  }
}
