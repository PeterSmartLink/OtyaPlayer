import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../my_space/data/media_repository.dart';
import '../../transfer/data/transfer_security_policy.dart';
import '../data/together_guest_storage.dart';
import '../data/together_stream_cache_proxy.dart';
import 'nearby_together_runtime.dart';
import 'nearby_together_session.dart';

/// Owns the guest media transport independently from the Together control room.
///
/// The control runtime can reconnect or close without becoming the owner of
/// media cache files. This service replaces a host LAN URL with an authenticated
/// loopback URL before the existing player opens it.
class TogetherGuestMediaSession extends ChangeNotifier {
  TogetherGuestMediaSession._() {
    NearbyTogetherRuntime.instance.addListener(_onTogetherRuntimeChanged);
  }

  static final instance = TogetherGuestMediaSession._();

  TogetherStreamCacheProxy? _proxy;
  StreamSubscription<double>? _progressSubscription;
  TogetherStreamMode? _mode;
  String? _suggestedName;
  String? _savedPath;
  String? _lastError;
  double _progress = 0;
  bool _finishing = false;
  bool _partialPreserved = false;

  TogetherStreamMode? get mode => _mode;
  bool get active => _proxy != null;
  bool get keepsVideo => _mode == TogetherStreamMode.streamAndSave;
  double get progress => _progress;
  String? get savedPath => _savedPath;
  String? get lastError => _lastError;
  bool get partialPreserved => _partialPreserved;

  Future<NearbyPlaybackPlan> prepare({
    required NearbyPlaybackPlan plan,
    required TogetherStreamMode mode,
  }) async {
    await _releaseCurrent(preserveCache: keepsVideo);
    _mode = null;
    _savedPath = null;
    _lastError = null;
    _progress = 0;
    _partialPreserved = false;

    if (plan.kind == NearbyPlaybackSourceKind.localCopy) {
      notifyListeners();
      return plan;
    }

    final upstream = plan.hostMediaUrl;
    if (upstream == null || !isAllowedTransferUri(upstream)) {
      throw StateError('Together host media source is invalid.');
    }

    Directory? cacheDirectory;
    if (mode == TogetherStreamMode.streamAndSave) {
      cacheDirectory = await TogetherGuestStorage.instance.cacheDirectory(
        plan.remoteMedia.fingerprint,
      );
    }

    final proxy = TogetherStreamCacheProxy();
    try {
      final local = await proxy.start(
        upstream: upstream,
        byteLength: plan.remoteMedia.byteLength,
        mediaFingerprint: plan.remoteMedia.fingerprint,
        mimeType: plan.remoteMedia.mimeType,
        mode: mode,
        cacheDirectory: cacheDirectory,
      );

      _proxy = proxy;
      _mode = mode;
      _suggestedName =
          TogetherGuestStorage.instance.suggestedNameFromUpstream(upstream);
      _progress = proxy.cachedFraction;
      _progressSubscription = proxy.progress.listen((value) {
        _progress = value;
        notifyListeners();
      });
      notifyListeners();

      if (mode == TogetherStreamMode.streamAndSave) {
        unawaited(_fillMissingInBackground(proxy));
      }

      return NearbyPlaybackPlan.stream(
        remoteMedia: plan.remoteMedia,
        hostMediaUrl: local,
        hostDisplayName: plan.hostDisplayName,
        hostUsername: plan.hostUsername,
      );
    } catch (_) {
      await proxy.dispose(deleteCache: mode == TogetherStreamMode.streamOnly);
      rethrow;
    }
  }

  /// The Keep-video mode fills missing fixed chunks while the room is alive.
  /// Playback requests share the same in-flight chunk futures, so this does not
  /// download a byte range twice when the player reaches a chunk being saved.
  Future<void> _fillMissingInBackground(TogetherStreamCacheProxy proxy) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!identical(_proxy, proxy) ||
        !NearbyTogetherRuntime.instance.active ||
        !keepsVideo) {
      return;
    }
    try {
      await proxy.completeSave();
    } catch (_) {
      if (!identical(_proxy, proxy)) return;
      _lastError =
          'Keep video paused. OTYA will reuse the received parts if you join this media again.';
      notifyListeners();
    }
  }

  void _onTogetherRuntimeChanged() {
    if (!NearbyTogetherRuntime.instance.active && _proxy != null) {
      unawaited(_finishAfterRoom());
    }
  }

  Future<void> _finishAfterRoom() async {
    if (_finishing) return;
    final proxy = _proxy;
    if (proxy == null) return;
    _finishing = true;

    try {
      if (keepsVideo && proxy.cachedBytes >= proxy.byteLength) {
        final destination = await TogetherGuestStorage.instance.nextReceivedFile(
          _suggestedName ?? 'Together video.mp4',
        );
        final saved = await proxy.finalizeTo(destination);
        MediaRepository.instance.invalidate();
        _savedPath = saved.path;
        _progress = 1;
        _partialPreserved = false;
        await _progressSubscription?.cancel();
        _progressSubscription = null;
        await proxy.dispose(deleteCache: false);
        if (identical(_proxy, proxy)) _proxy = null;
      } else {
        _partialPreserved = keepsVideo && proxy.cachedBytes > 0;
        await _releaseCurrent(preserveCache: keepsVideo);
      }
    } catch (_) {
      _lastError = keepsVideo
          ? 'OTYA kept the received parts, but could not finish saving the video yet.'
          : 'Together stream cleanup did not finish normally.';
      try {
        await _releaseCurrent(preserveCache: keepsVideo);
      } catch (_) {}
    } finally {
      _finishing = false;
      notifyListeners();
    }
  }

  Future<void> _releaseCurrent({required bool preserveCache}) async {
    final proxy = _proxy;
    _proxy = null;
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    if (proxy != null) {
      await proxy.dispose(deleteCache: !preserveCache);
    }
  }
}
