import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/core/services/fcm_service.dart').readAsStringSync();

  test('FCM keeps transient Firebase startup failures retryable', () {
    expect(source, contains('Future<void>? _initInFlight;'));
    expect(source, contains('final existing = _initInFlight;'));
    expect(source, contains('if (existing != null) return existing;'));

    final ensureIndex = source.indexOf(
      'if (!await FirebasePlatformService.instance.ensureInitialized()) return;',
    );
    final listenerGuardIndex = source.indexOf(
      'if (!_listenersAttached) {',
      ensureIndex,
    );
    final initializedIndex = source.indexOf(
      '_initialized = true;',
      listenerGuardIndex,
    );
    expect(ensureIndex, greaterThanOrEqualTo(0));
    expect(listenerGuardIndex, greaterThan(ensureIndex));
    expect(initializedIndex, greaterThan(listenerGuardIndex));
  });

  test('FCM listeners attach once while initial sync remains recoverable', () {
    expect(source, contains('bool _listenersAttached = false;'));
    expect(source, contains('if (!_listenersAttached) {'));
    expect(source, contains('FirebaseMessaging.onBackgroundMessage('));
    expect(source, contains('FirebaseMessaging.onMessage.listen('));
    expect(source, contains('FirebaseMessaging.onMessageOpenedApp.listen('));
    expect(source, contains('messaging.onTokenRefresh.listen('));
    expect(source, contains('_listenersAttached = true;'));
    expect(source, contains('initial message lookup failed (non-fatal)'));
    expect(source, contains('initial token sync failed (non-fatal)'));
  });

  test('FCM keeps every Android install on the bounded public broadcast topic', () {
    expect(source, contains("static const _publicTopic = 'otya_public';"));
    expect(source, contains('await messaging.subscribeToTopic(_publicTopic);'));
    expect(source, contains('_syncPublicTopic(messaging).ignore();'));
    expect(source, contains('public topic sync failed (non-fatal)'));
  });
}
