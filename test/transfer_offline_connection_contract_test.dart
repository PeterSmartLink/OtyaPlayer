import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otya_transfer_android/otya_transfer_android.dart';

void main() {
  test('Transfer owns a focused Android hotspot bridge', () {
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

  test('nearby hotspot QR is a standard Wi-Fi payload', () {
    const info = OtyaHotspotInfo(
      ssid: 'Otya;Nearby',
      passphrase: 'abc:123',
      securityType: 1,
    );

    expect(info.wifiQrPayload, startsWith('WIFI:T:WPA;'));
    expect(info.wifiQrPayload, contains(r'S:Otya\;Nearby'));
    expect(info.wifiQrPayload, contains(r'P:abc\:123'));
  });

  test('sender prefers real local adapters and exposes browser fallback', () {
    final source = File(
      'lib/features/transfer/data/media_sender.dart',
    ).readAsStringSync();

    expect(source, contains("name.startsWith('tun')"));
    expect(source, contains("name.startsWith('rmnet')"));
    expect(source, contains("name.contains('wlan')"));
    expect(source, contains("case '/media':"));
    expect(source, contains("case '/app':"));
    expect(source, contains('Otya Transfer'));
    expect(source, contains('Download Otya APK'));
    expect(source, contains('HttpHeaders.rangeHeader'));
    expect(source, contains('_tokenMatches(requestToken, _token)'));
  });

  test('Transfer UI separates categories and can create offline network', () {
    final screen = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();
    final hotspot = File(
      'lib/features/transfer/data/transfer_hotspot_service.dart',
    ).readAsStringSync();
    final entry = File(
      'lib/features/air_drop/presentation/air_drop_screen.dart',
    ).readAsStringSync();

    expect(screen, contains('_TransferCategory.video'));
    expect(screen, contains('_TransferCategory.music'));
    expect(screen, contains('_TransferCategory.app'));
    expect(screen, contains("label: 'Video'"));
    expect(screen, contains("label: 'Music'"));
    expect(screen, contains("label: 'Otya'"));
    expect(screen, contains('_HotspotJoinCard'));
    expect(screen, contains('Receive without Otya'));
    expect(screen, contains('isAllowedTransferUri(uri)'));
    expect(screen, isNot(contains('bool _isPrivateHost(')));

    expect(hotspot, contains('ensureLocalNetworkAccess()'));
    expect(hotspot, contains('Permission.nearbyWifiDevices.request()'));
    expect(hotspot, contains('Permission.locationWhenInUse.request()'));
    expect(hotspot, contains('startLocalOnlyHotspot()'));
    expect(
      entry,
      contains('TransferHotspotService.instance.ensureLocalNetworkAccess()'),
    );
    expect(entry, contains('const TransferScreen()'));
  });
}
