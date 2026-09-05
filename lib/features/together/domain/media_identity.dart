/// OTYA media identity contract.
///
/// A fingerprint allows OTYA to determine that two differently named files are
/// the same media without exposing the user's local path. The fingerprinting
/// algorithm itself is intentionally kept out of this domain model so it can be
/// benchmarked for speed, collision resistance, battery use, and APK impact
/// before becoming part of production playback.
class OtyaMediaIdentity {
  final String fingerprint;
  final int byteLength;
  final Duration? duration;
  final String? mimeType;

  const OtyaMediaIdentity({
    required this.fingerprint,
    required this.byteLength,
    this.duration,
    this.mimeType,
  });

  bool sameMediaAs(OtyaMediaIdentity other) {
    return fingerprint == other.fingerprint && byteLength == other.byteLength;
  }
}

enum PeerMediaAvailability {
  missing,
  partial,
  complete,
}

class MediaByteRange {
  final int start;
  final int endExclusive;

  const MediaByteRange({
    required this.start,
    required this.endExclusive,
  }) : assert(start >= 0),
       assert(endExclusive > start);

  int get length => endExclusive - start;

  bool contains(int offset) => offset >= start && offset < endExclusive;
}

class PeerMediaState {
  final OtyaMediaIdentity identity;
  final PeerMediaAvailability availability;

  /// Ranges the peer already owns when [availability] is partial.
  final List<MediaByteRange> availableRanges;

  const PeerMediaState({
    required this.identity,
    required this.availability,
    this.availableRanges = const [],
  });

  bool get needsMediaBytes => availability != PeerMediaAvailability.complete;
}
