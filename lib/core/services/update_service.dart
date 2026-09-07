import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/environment.dart';
import 'push_notification_service.dart';

enum UpdateCheckState {
  idle,
  checking,
  current,
  updateAvailable,
  unavailable,
  skipped,
  preRelease,
}

/// Checks the canonical public Otya release authority.
///
/// A direct PeterSmart Link APK may offer the PeterSmart Link release page.
/// Google Play builds never sideload from that channel. Release truth comes
/// from /latest and is accepted only when the server marks it published and
/// its immutable tag, public version and build number agree.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _prefLastCheck = 'update_last_check';
  static final RegExp _releaseTag = RegExp(r'^v(\d+\.\d+\.\d+)\+([1-9]\d*)$');
  static const Set<String> _officialHosts = {
    'petersmartlink.com',
    'www.petersmartlink.com',
  };

  Future<UpdateInfo?>? _checkInFlight;
  bool _checkInFlightForced = false;
  UpdateCheckState _lastState = UpdateCheckState.idle;
  String? _lastError;

  UpdateCheckState get lastState => _lastState;
  String? get lastError => _lastError;
  String get downloadUrl => Environment.downloadPageUrl;

  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    final existing = _checkInFlight;
    if (existing != null) {
      final existingWasForced = _checkInFlightForced;
      _lastState = UpdateCheckState.checking;
      final result = await existing;
      if (force && !existingWasForced && _lastState == UpdateCheckState.skipped) {
        return checkForUpdate(force: true);
      }
      return result;
    }

    _lastState = UpdateCheckState.checking;
    _lastError = null;
    final check = _doCheckForUpdate(force: force);
    _checkInFlight = check;
    _checkInFlightForced = force;
    try {
      return await check;
    } finally {
      if (identical(_checkInFlight, check)) {
        _checkInFlight = null;
        _checkInFlightForced = false;
      }
    }
  }

  Future<UpdateInfo?> _doCheckForUpdate({bool force = false}) async {
    try {
      // Google Play owns updates for Play-distributed builds. Do not point a
      // Play build at a direct APK channel merely because the server has a
      // newer PeterSmart Link build.
      if (!Environment.selfUpdateEnabled) {
        _lastState = UpdateCheckState.skipped;
        _lastError = 'Updates for this build are managed by Google Play.';
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final lastCheck = prefs.getInt(_prefLastCheck) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastCheck < const Duration(hours: 24).inMilliseconds) {
          debugPrint('[UpdateService] Skipping check — checked within 24h.');
          _lastState = UpdateCheckState.skipped;
          return null;
        }
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      http.Response? response;
      try {
        response = await http.get(
          Uri.parse(Environment.latestUrl),
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        ).timeout(const Duration(seconds: 10));
      } catch (_) {}

      if (response == null || response.statusCode != 200) {
        _lastState = UpdateCheckState.unavailable;
        _lastError = response == null
            ? 'Otya could not reach the public release service.'
            : 'Release service returned HTTP ${response.statusCode}.';
        debugPrint('[UpdateService] Canonical /latest failed: $_lastError');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _lastState = UpdateCheckState.unavailable;
        _lastError = 'Release service returned invalid data.';
        return null;
      }
      final data = decoded;

      if (data['published'] != true) {
        _lastState = UpdateCheckState.preRelease;
        _lastError = 'No public Otya release is published yet.';
        await prefs.setInt(_prefLastCheck, DateTime.now().millisecondsSinceEpoch);
        return null;
      }

      final serverVersionCode = (data['versionCode'] as num?)?.toInt() ?? 0;
      final serverVersion = (data['version'] as String? ?? '').trim();
      final tag = (data['tag'] as String? ?? '').trim();
      final tagMatch = _releaseTag.firstMatch(tag);
      final tagBuild = tagMatch == null ? 0 : int.tryParse(tagMatch.group(2) ?? '') ?? 0;

      if (serverVersionCode <= 0 ||
          serverVersion.isEmpty ||
          tagMatch == null ||
          tagMatch.group(1) != serverVersion ||
          tagBuild != serverVersionCode) {
        _lastState = UpdateCheckState.unavailable;
        _lastError = 'Published release identity is inconsistent.';
        return null;
      }

      final rawDownloads = data['downloads'];
      final downloads = rawDownloads is Map<String, dynamic>
          ? rawDownloads
          : <String, dynamic>{};
      final abi = _detectAbi();
      if (abi != 'arm64' && abi != 'arm32') {
        _lastState = UpdateCheckState.unavailable;
        _lastError = 'This Android CPU architecture is not supported by the direct update channel.';
        return null;
      }

      final exactKey = abi == 'arm64' ? 'exactArm64' : 'exactArm32';
      final aliasKey = abi == 'arm64' ? 'arm64' : 'arm32';
      final rawDirect = downloads[exactKey] ?? downloads[aliasKey];
      final directUrl = _officialHttps(rawDirect);
      final pageUrl = _officialHttps(downloads['auto']) ??
          _officialHttps(Environment.downloadPageUrl);
      if (directUrl == null || pageUrl == null) {
        _lastState = UpdateCheckState.unavailable;
        _lastError = 'Published release does not contain a verified Otya download destination.';
        return null;
      }

      await prefs.setInt(_prefLastCheck, DateTime.now().millisecondsSinceEpoch);
      debugPrint(
        '[UpdateService] Installed: $installedCode  Published: $serverVersionCode ($tag)',
      );

      if (serverVersionCode <= installedCode) {
        _lastState = UpdateCheckState.current;
        return null;
      }

      _lastState = UpdateCheckState.updateAvailable;
      return UpdateInfo(
        tag: tag,
        version: serverVersion,
        versionCode: serverVersionCode,
        installedCode: installedCode,
        changelog: data['changelog'] as String? ?? '',
        downloadUrl: pageUrl,
        directUrl: directUrl,
        releaseDate: data['date'] as String? ?? '',
      );
    } catch (e) {
      _lastState = UpdateCheckState.unavailable;
      _lastError = 'Update check failed: ${e.runtimeType}';
      debugPrint('[UpdateService] Check failed: $e');
      return null;
    }
  }

  String? _officialHttps(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !_officialHosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    return uri.toString();
  }

  Future<void> checkAndNotify() async {
    final info = await checkForUpdate();
    if (info == null) return;
    await PushNotificationService.instance.showUpdateNotification(
      version: info.version,
      releaseNotes: info.changelog,
      downloadUrl: info.downloadUrl,
    );
  }

  Future<void> remindLater(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastCheck, DateTime.now().millisecondsSinceEpoch);
    debugPrint('[UpdateService] Remind later for build $versionCode.');
  }

  String _detectAbi() => Environment.appArch;
}

class UpdateInfo {
  final String tag;
  final String version;
  final int versionCode;
  final int installedCode;
  final String changelog;
  final String downloadUrl;
  final String directUrl;
  final String releaseDate;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.versionCode,
    required this.installedCode,
    required this.changelog,
    required this.downloadUrl,
    required this.directUrl,
    required this.releaseDate,
  });
}
