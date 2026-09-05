import 'dart:io';

import 'package:flutter/services.dart';

class OtyaHotspotInfo {
  const OtyaHotspotInfo({
    required this.ssid,
    required this.passphrase,
    required this.securityType,
  });

  final String ssid;
  final String? passphrase;
  final int securityType;

  String get wifiQrPayload {
    final escapedSsid = _wifiEscape(ssid);
    final escapedPassword = _wifiEscape(passphrase ?? '');
    final auth = (passphrase == null || passphrase!.isEmpty) ? 'nopass' : 'WPA';
    return 'WIFI:T:$auth;S:$escapedSsid;P:$escapedPassword;;';
  }

  static String _wifiEscape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll(':', '\\:')
      .replaceAll('"', '\\"');
}

class OtyaShareableApk {
  const OtyaShareableApk({
    required this.available,
    this.path,
    this.bytes = 0,
    this.splitCount = 0,
    this.reason,
  });

  final bool available;
  final String? path;
  final int bytes;
  final int splitCount;
  final String? reason;
}

class OtyaTransferAndroid {
  OtyaTransferAndroid._();

  static const MethodChannel _channel =
      MethodChannel('com.otyaplayer.app/transfer_android');

  static bool get isSupportedPlatform => Platform.isAndroid;

  static Future<int> sdkInt() async {
    if (!Platform.isAndroid) return -1;
    return await _channel.invokeMethod<int>('sdkInt') ?? -1;
  }

  static Future<OtyaHotspotInfo> startLocalOnlyHotspot() async {
    if (!Platform.isAndroid) {
      throw PlatformException(
        code: 'HOTSPOT_UNSUPPORTED',
        message: 'Offline hotspot is currently available on Android only.',
      );
    }

    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'startLocalOnlyHotspot',
    );
    final ssid = raw?['ssid']?.toString().trim() ?? '';
    if (ssid.isEmpty) {
      throw PlatformException(
        code: 'HOTSPOT_FAILED',
        message: 'Android started a hotspot without usable connection details.',
      );
    }
    return OtyaHotspotInfo(
      ssid: ssid,
      passphrase: raw?['passphrase']?.toString(),
      securityType: (raw?['securityType'] as num?)?.toInt() ?? -1,
    );
  }

  static Future<void> stopLocalOnlyHotspot() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopLocalOnlyHotspot');
  }

  static Future<OtyaShareableApk> getShareableApk() async {
    if (!Platform.isAndroid) {
      return const OtyaShareableApk(
        available: false,
        reason: 'Otya APK sharing is currently available on Android only.',
      );
    }

    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'getShareableApk',
    );
    return OtyaShareableApk(
      available: raw?['available'] == true,
      path: raw?['path']?.toString(),
      bytes: (raw?['bytes'] as num?)?.toInt() ?? 0,
      splitCount: (raw?['splitCount'] as num?)?.toInt() ?? 0,
      reason: raw?['reason']?.toString(),
    );
  }
}
