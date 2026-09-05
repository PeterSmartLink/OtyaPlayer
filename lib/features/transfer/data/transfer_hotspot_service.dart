import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:otya_transfer_android/otya_transfer_android.dart';
import 'package:permission_handler/permission_handler.dart';

class TransferHotspotException implements Exception {
  const TransferHotspotException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class TransferHotspotService {
  TransferHotspotService._();
  static final TransferHotspotService instance = TransferHotspotService._();

  OtyaHotspotInfo? _active;

  OtyaHotspotInfo? get active => _active;

  /// Requests the nearby-device permission only when the user enters Transfer.
  ///
  /// Android 13+ uses this permission for Wi-Fi connection management, and
  /// Android 16's local-network protection path also uses it to restore raw
  /// LAN socket access. Android 8-12 do not need location for ordinary TCP
  /// transfer, so their location prompt remains deferred until hotspot
  /// creation actually needs it.
  Future<bool> ensureLocalNetworkAccess() async {
    if (!Platform.isAndroid) return true;
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk < 33) return true;

    final current = await Permission.nearbyWifiDevices.status;
    if (current.isGranted) return true;
    final requested = await Permission.nearbyWifiDevices.request();
    return requested.isGranted;
  }

  Future<OtyaHotspotInfo?> start() async {
    if (!Platform.isAndroid) return null;

    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    PermissionStatus permission;
    if (sdk >= 33) {
      final granted = await ensureLocalNetworkAccess();
      permission = granted
          ? PermissionStatus.granted
          : await Permission.nearbyWifiDevices.status;
    } else if (sdk >= 26) {
      permission = await Permission.locationWhenInUse.request();
    } else {
      throw const TransferHotspotException(
        'Automatic offline hotspot requires Android 8.0 or newer.',
        code: 'HOTSPOT_UNSUPPORTED',
      );
    }

    if (!permission.isGranted) {
      throw TransferHotspotException(
        sdk >= 33
            ? 'Allow Nearby devices so Otya can connect directly to nearby phones and create an offline Transfer hotspot.'
            : 'Allow location while using Otya. Android requires it for local-only hotspots on this version.',
        code: 'HOTSPOT_PERMISSION_REQUIRED',
      );
    }

    try {
      final info = await OtyaTransferAndroid.startLocalOnlyHotspot();
      _active = info;
      return info;
    } on PlatformException catch (error) {
      throw TransferHotspotException(
        error.message ?? 'Android could not create the offline Otya hotspot.',
        code: error.code,
      );
    }
  }

  Future<void> stop() async {
    _active = null;
    if (!Platform.isAndroid) return;
    try {
      await OtyaTransferAndroid.stopLocalOnlyHotspot();
    } on PlatformException {
      // The Android reservation may already have been stopped by the user.
    }
  }

  Future<OtyaShareableApk> shareableApk() async {
    try {
      return await OtyaTransferAndroid.getShareableApk();
    } on PlatformException catch (error) {
      return OtyaShareableApk(
        available: false,
        reason: error.message ??
            'Android could not prepare Otya for offline sharing.',
      );
    }
  }
}
