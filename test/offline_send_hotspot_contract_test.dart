import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otya_transfer_android/otya_transfer_android.dart';

void main() {
  test('Send owns a focused first-party Android hotspot bridge', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File(
      'packages/otya_transfer_android/android/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final plugin = File(
      'packages/otya_transfer_android/android/src/main/kotlin/com/petersmartlink/otya_transfer_android/OtyaTransferAndroidPlugin.kt',
    ).readAsStringSync();

    expect(pubspec, contains('otya_transfer_android:'));
    expect(pubspec, contains('path: packages/otya_transfer_android'));
    expect(manifest, contains('android.permission.CHANGE_WIFI_STATE'));
    expect(manifest, contains('android.permission.NEARBY_WIFI_DEVICES'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(plugin, contains('startLocalOnlyHotspot'));
    expect(plugin, contains('LocalOnlyHotspotReservation'));
    expect(plugin, contains('splitSourceDirs'));
    expect(
      plugin,
      contains('sharing only the base APK would create a broken installer'),
    );
  });

  test('hotspot QR is a standard Wi-Fi payload', () {
    const info = OtyaHotspotInfo(
      ssid: 'Otya;Nearby',
      passphrase: 'abc:123',
      securityType: 1,
    );

    expect(info.wifiQrPayload, startsWith('WIFI:T:WPA;'));
    expect(info.wifiQrPayload, contains(r'S:Otya\;Nearby'));
    expect(info.wifiQrPayload, contains(r'P:abc\:123'));
  });

  test('Send is connection-first without exposing an Offline network mini-feature', () {
    final entry = File(
      'lib/features/air_drop/presentation/air_drop_screen.dart',
    ).readAsStringSync();
    final transfer = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();
    final hotspot = File(
      'lib/features/transfer/data/transfer_hotspot_service.dart',
    ).readAsStringSync();
    final router = File('lib/app/router.dart').readAsStringSync();

    expect(entry, contains('const TransferScreen()'));
    expect(entry, isNot(contains("'Offline network'")));
    expect(entry, isNot(contains('FloatingActionButton')));

    expect(transfer, contains("primaryLabel: 'Create hotspot'"));
    expect(transfer, contains("secondaryLabel: 'Use current Wi-Fi'"));
    expect(transfer, contains("title: 'Connect to the sender'"));
    expect(transfer, contains("label: 'Videos'"));
    expect(transfer, contains("label: 'Music'"));
    expect(transfer, contains("Received/$folder"));
    expect(transfer, isNot(contains('Local network only')));
    expect(transfer, isNot(contains('Offline network')));

    expect(hotspot, contains('ensureLocalNetworkAccess()'));
    expect(hotspot, contains('Permission.nearbyWifiDevices.request()'));
    expect(hotspot, contains('Permission.locationWhenInUse.request()'));
    expect(hotspot, contains('startLocalOnlyHotspot()'));

    expect(router, contains("static const _routes = ['/', '/music', '/myspace']"));
    expect(router, isNot(contains("label: 'Transfer'")));
    expect(router, isNot(contains("label: 'Together'")));
  });
}
