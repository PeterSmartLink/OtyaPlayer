// lib/core/services/device_service.dart
//
// Registers this device with the Worker on first launch and updates
// the record whenever the app version changes.
//
// Only calls the network when the build number has changed
// (stored in SharedPreferences as 'otya_registered_build').

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/environment.dart';
import 'api_signer.dart';
import 'firebase_platform_service.dart';
import 'http_client.dart';

const _kDeviceId = 'otya_device_id';
const _kRegisteredBuild = 'otya_registered_build';

class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  final _http = AppHttpClient.instance;
  final _deviceInfo = DeviceInfoPlugin();
  String? _cachedDeviceId;

  /// Returns the stable device ID (generated once, stored in SharedPreferences).
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_kDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_kDeviceId, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// Registers (or updates) this device on the Worker.
  /// Only calls the network when the build number has changed.
  Future<void> registerIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = packageInfo.buildNumber;

      if (prefs.getString(_kRegisteredBuild) == currentBuild) return;

      final deviceId = await getDeviceId();
      String model = 'unknown';
      String androidVersion = 'unknown';

      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        model = '${android.manufacturer} ${android.model}';
        androidVersion = android.version.release;
      }

      const path = '/api/device';
      final signedHeaders = {
        ...ApiSigner.signedHeaders(
          method: 'POST',
          path: path,
          deviceId: deviceId,
        ),
        'Content-Type': 'application/json',
      };
      // App Check is optional/non-fatal on the client, but attaching it here
      // makes this route ready for server-side enforcement without a new APK.
      final headers = await FirebasePlatformService.instance.protectedHeaders(
        base: signedHeaders,
      );

      final body = jsonEncode({
        'device_id': deviceId,
        'model': model,
        'android_version': androidVersion,
        'app_version': packageInfo.version,
        'app_build': int.tryParse(currentBuild) ?? 0,
        'arch': Environment.appArch,
        'locale': Platform.localeName,
      });

      final response = await _http.post(
        Uri.parse('${Environment.workerUrl}$path'),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        await prefs.setString(_kRegisteredBuild, currentBuild);
        if (kDebugMode) {
          debugPrint('[DeviceService] registration completed');
        }
      } else {
        debugPrint(
          '[DeviceService] registration returned ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[DeviceService] error (non-fatal): $e');
    }
  }
}
