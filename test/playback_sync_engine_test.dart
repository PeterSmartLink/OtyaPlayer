import 'package:flutter_test/flutter_test.dart';
import 'package:otya_player/features/together/application/playback_sync_engine.dart';

TogetherPlaybackState state({
  int sequence = 1,
  int revision = 0,
  bool playing = true,
  int positionMs = 10000,
  int sentUs = 1000000,
  double rate = 1,
}) =>
    TogetherPlaybackState(
      sequence: sequence,
      mediaRevision: revision,
      playing: playing,
      positionMs: positionMs,
      sentMonotonicUs: sentUs,
      rate: rate,
    );

void main() {
  test('lowest RTT clock sample wins', () {
    final engine = PlaybackSyncEngine();
    engine.addClockSample(const TogetherClockSample(
      guestSendUs: 1000,
      hostReplyUs: 2600,
      guestReceiveUs: 3000,
    ));
    expect(engine.remoteMinusLocalUs, 600);

    // Higher RTT must not replace the lower-latency estimate.
    engine.addClockSample(const TogetherClockSample(
      guestSendUs: 1000,
      hostReplyUs: 9000,
      guestReceiveUs: 11000,
    ));
    expect(engine.remoteMinusLocalUs, 600);
  });

  test('small drift needs no seek or speed change', () {
    final engine = PlaybackSyncEngine();
    final correction = engine.accept(
      remote: state(positionMs: 10000, sentUs: 1000000),
      localNowUs: 1100000,
      currentPositionMs: 10130,
      currentPlaying: true,
    );

    expect(correction, isNotNull);
    expect(correction!.expectedPositionMs, 10100);
    expect(correction.driftMs, 30);
    expect(correction.kind, PlaybackCorrectionKind.none);
    expect(correction.playbackSpeed, 1);
  });

  test('guest behind softly catches up without jumping', () {
    final engine = PlaybackSyncEngine();
    final correction = engine.accept(
      remote: state(positionMs: 10000, sentUs: 1000000),
      localNowUs: 1100000,
      currentPositionMs: 9950,
      currentPlaying: true,
    );

    expect(correction!.driftMs, -150);
    expect(correction.kind, PlaybackCorrectionKind.speed);
    expect(correction.playbackSpeed, PlaybackSyncEngine.catchUpSpeed);
  });

  test('large drift produces an authoritative hard seek', () {
    final engine = PlaybackSyncEngine();
    final correction = engine.accept(
      remote: state(positionMs: 10000, sentUs: 1000000),
      localNowUs: 1100000,
      currentPositionMs: 9000,
      currentPlaying: true,
    );

    expect(correction!.kind, PlaybackCorrectionKind.seek);
    expect(correction.expectedPositionMs, 10100);
    expect(correction.requiresSeek, isTrue);
  });

  test('pause packets do not advance position with network time', () {
    final engine = PlaybackSyncEngine();
    final correction = engine.accept(
      remote: state(
        playing: false,
        positionMs: 45023,
        sentUs: 1000000,
      ),
      localNowUs: 6000000,
      currentPositionMs: 45023,
      currentPlaying: true,
    );

    expect(correction!.expectedPositionMs, 45023);
    expect(correction.shouldPlay, isFalse);
    expect(correction.kind, PlaybackCorrectionKind.none);
  });

  test('stale sequence is rejected', () {
    final engine = PlaybackSyncEngine();
    expect(
      engine.accept(
        remote: state(sequence: 4),
        localNowUs: 1000000,
        currentPositionMs: 10000,
        currentPlaying: true,
      ),
      isNotNull,
    );
    expect(
      engine.accept(
        remote: state(sequence: 4),
        localNowUs: 1000000,
        currentPositionMs: 10000,
        currentPlaying: true,
      ),
      isNull,
    );
  });

  test('old movie packets are rejected after next media starts', () {
    final engine = PlaybackSyncEngine()..resetForMediaRevision(3);

    expect(
      engine.accept(
        remote: state(sequence: 1, revision: 2),
        localNowUs: 1000000,
        currentPositionMs: 10000,
        currentPlaying: true,
      ),
      isNull,
    );

    expect(
      engine.accept(
        remote: state(sequence: 1, revision: 3),
        localNowUs: 1000000,
        currentPositionMs: 10000,
        currentPlaying: true,
      ),
      isNotNull,
    );
  });
}
