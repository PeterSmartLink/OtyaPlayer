import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_client.dart';
import '../config/environment.dart';

class RemoteControlService extends ChangeNotifier {
  RemoteControlService._();
  static final RemoteControlService instance = RemoteControlService._();

  static const _url = Environment.appConfigUrl;
  static const _cacheKey = 'otya_remote_control_cache_v1';
  static const _bucketSeedKey = 'otya_remote_bucket_seed_v1';
  static const _seenAnnouncementPrefix = 'otya_remote_announcement_seen_';

  Map<String, dynamic> _config = const {};
  bool _loaded = false;
  bool _onlineFresh = false;
  Future<bool>? _refreshInFlight;
  String _bucketSeed = 'otya-default';

  bool get loaded => _loaded;
  bool get onlineFresh => _onlineFresh;
  Map<String, dynamic> get config => Map.unmodifiable(_config);

  Future<void> init({bool refresh = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _bucketSeed = prefs.getString(_bucketSeedKey) ?? _newBucketSeed();
    if (!prefs.containsKey(_bucketSeedKey)) {
      await prefs.setString(_bucketSeedKey, _bucketSeed);
    }

    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) _config = decoded;
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
    if (refresh) await refreshFromServer();
  }

  Future<bool> refreshFromServer() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final attempt = _refresh();
    _refreshInFlight = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_refreshInFlight, attempt)) _refreshInFlight = null;
    }
  }

  Future<bool> _refresh() async {
    var receivedFreshConfig = false;
    try {
      final timeoutSeconds = _int(runtime['apiTimeoutSeconds'], 8).clamp(4, 30);
      final response = await AppHttpClient.instance.client
          .get(
            Uri.parse(_url),
            headers: const {
              'Accept': 'application/json',
              'Accept-Encoding': 'gzip, deflate',
            },
          )
          .timeout(Duration(seconds: timeoutSeconds));
      if (response.statusCode != 200 || response.body.trim().isEmpty) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      final config = decoded['config'];
      if (config is! Map<String, dynamic>) return false;
      _config = config;
      receivedFreshConfig = true;
      _loaded = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(_config));
      } catch (_) {
        debugPrint('[RemoteControl] Could not cache current configuration.');
      }
      return true;
    } catch (_) {
      debugPrint('[RemoteControl] Refresh failed; using saved configuration.');
      return false;
    } finally {
      _onlineFresh = receivedFreshConfig;
      notifyListeners();
    }
  }

  bool featureEnabled(String key, {bool fallback = true}) {
    final features = _config['features'];
    if (features is Map && features[key] is bool) return features[key] as bool;
    return fallback;
  }

  Map<String, dynamic> get maintenance => _map(_config['maintenance']);

  bool get maintenanceEnabled => maintenance['enabled'] == true;
  bool get allowOfflinePlayback => maintenance['allowOfflinePlayback'] != false;

  Map<String, dynamic> get links => _map(_config['links']);
  String link(String key, String fallback) => links[key]?.toString() ?? fallback;

  Map<String, dynamic> get home => _map(_config['home']);
  Map<String, dynamic> get ai => _map(_config['ai']);
  Map<String, dynamic> get search => _map(_config['search']);
  Map<String, dynamic> get runtime => _map(_config['runtime']);
  List<dynamic> get campaigns =>
      _config['campaigns'] is List ? _config['campaigns'] as List : const [];

  Future<RemoteVersionState> versionState() async {
    final versions = _map(_config['versions']);
    final package = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(package.buildNumber) ?? 0;
    final minimum = _int(versions['minimumBuild'], 0);
    final recommended = _int(versions['recommendedBuild'], minimum);
    return RemoteVersionState(
      currentBuild: currentBuild,
      minimumBuild: minimum,
      recommendedBuild: recommended,
      forceUpdate: versions['forceUpdate'] == true || currentBuild < minimum,
      updateRecommended: currentBuild < recommended,
    );
  }

  Future<Map<String, dynamic>?> pendingAnnouncement() async {
    final item = _config['announcement'];
    if (item is! Map) return null;
    final announcement = item.map((k, v) => MapEntry(k.toString(), v));
    if (announcement['enabled'] == false) return null;
    final id = announcement['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_seenAnnouncementPrefix$id') == true) return null;
    return announcement;
  }

  Future<void> markAnnouncementSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_seenAnnouncementPrefix$id', true);
  }

  bool experimentEnabled(String key, {bool fallback = false}) {
    final experiments = _config['experiments'];
    if (experiments is! Map || experiments[key] is! Map) return fallback;
    final exp = experiments[key] as Map;
    if (exp['enabled'] == false) return false;
    final percent = _int(exp['rolloutPercent'], 100).clamp(0, 100);
    if (percent <= 0) return false;
    if (percent >= 100) return true;
    final seed = '${exp['salt'] ?? key}:$key:$_bucketSeed';
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = ((hash * 31) + c) & 0x7fffffff;
    }
    return hash % 100 < percent;
  }

  static String _newBucketSeed() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }

  static int _int(dynamic value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}

class RemoteVersionState {
  const RemoteVersionState({
    required this.currentBuild,
    required this.minimumBuild,
    required this.recommendedBuild,
    required this.forceUpdate,
    required this.updateRecommended,
  });

  final int currentBuild;
  final int minimumBuild;
  final int recommendedBuild;
  final bool forceUpdate;
  final bool updateRecommended;
}
