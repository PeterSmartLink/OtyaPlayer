// lib/core/services/connectivity_service.dart
//
// Wraps connectivity_plus to provide:
//   - Synchronous isOffline getter (updated by a background stream listener).
//   - Stream<bool> offlineStream for UI widgets to react to connectivity changes.
//   - Static isOnline() helper (async, used by service layer).
//
// Bug 10 fix: all API call sites should check ConnectivityService.instance.isOffline
// before making network requests and return cached Hive data immediately when offline.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  // Current connectivity state — updated by the stream listener.
  bool _isOffline = false;

  /// True when the device has no active network connection.
  bool get isOffline => _isOffline;

  /// True when the device has at least one active network connection.
  bool get isOnline => !_isOffline;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Future<void>? _initInFlight;
  bool _initialized = false;

  // Broadcast stream so multiple widgets can listen.
  final StreamController<bool> _offlineController =
      StreamController<bool>.broadcast();

  /// Stream that emits `true` when offline, `false` when online.
  Stream<bool> get offlineStream => _offlineController.stream;

  /// Initialize the service. Call once from main() or _initBackground().
  Future<void> init() {
    if (_initialized) return Future<void>.value();
    final existing = _initInFlight;
    if (existing != null) return existing;

    final attempt = _initOnce();
    _initInFlight = attempt;
    return attempt.whenComplete(() {
      if (identical(_initInFlight, attempt)) _initInFlight = null;
    });
  }

  Future<void> _initOnce() async {
    // Perform an immediate check so isOffline is accurate before the first
    // stream event arrives.
    await _checkNow();

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) {
        _isOffline = offline;
        _offlineController.add(offline);
        debugPrint('[Connectivity] ${offline ? "OFFLINE" : "ONLINE"}');
      }
    });
    _initialized = true;
  }

  Future<void> _checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOffline = results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      _isOffline = false; // assume online if check fails
    }
  }

  /// One-shot async check. Returns true if online.
  /// Prefer [isOnline] for synchronous access after [init] has been called.
  static Future<bool> checkIsOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true; // assume online if check fails
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
    _offlineController.close();
  }
}
