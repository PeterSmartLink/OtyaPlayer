import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/media_identity.dart';

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Fast, privacy-conscious identity for peer media matching.
///
/// Large files are not read end-to-end. OTYA hashes a small set of deterministic
/// byte windows plus the exact byte length. This keeps identification cost
/// bounded even for multi-gigabyte movies.
///
/// Important: this fingerprint is a *matching hint*, not a security primitive.
/// A completed saved transfer must still use its independent integrity checks.
/// Fingerprints are exchanged peer-to-peer and must not be sent to the OTYA
/// room/signaling backend.
class MediaFingerprintService {
  MediaFingerprintService._();

  static final instance = MediaFingerprintService._();

  static const int _sampleBytes = 256 * 1024;
  static const int _wholeFileThreshold = 2 * 1024 * 1024;
  static const String _version = 's1';

  Future<OtyaMediaIdentity> identify({
    required String filePath,
    Duration? duration,
    String? mimeType,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Media file not found', filePath);
    }

    final byteLength = await file.length();
    if (byteLength <= 0) {
      throw FileSystemException('Media file is empty', filePath);
    }

    final fingerprint = byteLength <= _wholeFileThreshold
        ? await _hashWholeFile(file, byteLength)
        : await _hashSamples(file, byteLength);

    return OtyaMediaIdentity(
      fingerprint: '$_version:$fingerprint',
      byteLength: byteLength,
      duration: duration,
      mimeType: mimeType,
    );
  }

  Future<String> _hashWholeFile(File file, int byteLength) async {
    final sink = _DigestSink();
    final converter = sha256.startChunkedConversion(sink);
    converter.add(utf8.encode('OTYA_MEDIA|$_version|whole|$byteLength|'));
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    final digest = sink.value;
    if (digest == null) throw StateError('Could not fingerprint media file.');
    return digest.toString();
  }

  Future<String> _hashSamples(File file, int byteLength) async {
    final starts = _sampleStarts(byteLength);
    final raf = await file.open(mode: FileMode.read);
    try {
      final sink = _DigestSink();
      final converter = sha256.startChunkedConversion(sink);
      converter.add(utf8.encode(
        'OTYA_MEDIA|$_version|sampled|$byteLength|${starts.length}|$_sampleBytes|',
      ));

      for (final start in starts) {
        await raf.setPosition(start);
        final remaining = byteLength - start;
        final wanted = remaining < _sampleBytes ? remaining : _sampleBytes;
        final bytes = await raf.read(wanted);

        // Position and actual length are part of the digest so identical sample
        // bytes at different positions cannot be rearranged into the same input.
        converter.add(_uint64(start));
        converter.add(_uint32(bytes.length));
        converter.add(bytes);
      }

      converter.close();
      final digest = sink.value;
      if (digest == null) throw StateError('Could not fingerprint media file.');
      return digest.toString();
    } finally {
      await raf.close();
    }
  }

  List<int> _sampleStarts(int byteLength) {
    final maxStart = byteLength - _sampleBytes;
    if (maxStart <= 0) return const [0];

    // Five deterministic windows cover beginning, quarters, middle and end.
    // A set removes overlap for smaller files just over the whole-file cutoff.
    final starts = <int>{
      0,
      (maxStart * 0.25).floor(),
      (maxStart * 0.50).floor(),
      (maxStart * 0.75).floor(),
      maxStart,
    }.toList()
      ..sort();
    return starts;
  }

  Uint8List _uint64(int value) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setUint64(0, value, Endian.big);
    return bytes;
  }

  Uint8List _uint32(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
    return bytes;
  }
}
