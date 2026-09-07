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

  /// Requests nearby-device access only when the user enters Send/Transfer.
  /// Core playback remains permission-independent and offline-first.
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
            ? 'Allow Nearby devices so Otya can connect directly to nearby phones and create an offline Send hotspot.'
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
      // Android may already have stopped the reservation when Wi-Fi changes.
    }
  }

  Future<OtyaShareableApk> shareableApk() async {
    try {
      return await OtyaTransferAndroid.getShareableApk();
    } on PlatformException catch (error) {
      return OtyaShareableApk(
        available: false,
        reason: error.message ?? 'Android could not prepare Otya for offline sharing.',
      );
    }
  }
}
