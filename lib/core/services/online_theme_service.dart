import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'http_client.dart';
import '../config/environment.dart';

class OnlineTheme {
  const OnlineTheme({
    required this.id,
    required this.name,
    required this.story,
    required this.scene,
    required this.version,
    required this.overlay,
    required this.palette,
    this.previewUrl,
    this.wallpaperUrl,
    this.seasonal,
  });

  final String id;
  final String name;
  final String story;
  final String scene;
  final int version;
  final double overlay;
  final Map<String, String> palette;
  final String? previewUrl;
  final String? wallpaperUrl;
  final Map<String, dynamic>? seasonal;

  bool get isSeasonal => seasonal != null;
  bool get autoApply => seasonal?['autoApply'] == true;
  int get seasonalPriority => (seasonal?['priority'] as num?)?.toInt() ?? 0;

  bool isActiveOn(DateTime date) {
    final start = seasonal?['start'] as String?;
    final end = seasonal?['end'] as String?;
    if (start == null || end == null) return false;

    DateTime? parseMonthDay(String value, int year) {
      final parts = value.split('-');
      if (parts.length != 2) return null;
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      if (month == null || day == null) return null;
      return DateTime(year, month, day);
    }

    final startThisYear = parseMonthDay(start, date.year);
    final endThisYear = parseMonthDay(end, date.year);
    if (startThisYear == null || endThisYear == null) return false;

    final today = DateTime(date.year, date.month, date.day);
    if (!endThisYear.isBefore(startThisYear)) {
      return !today.isBefore(startThisYear) && !today.isAfter(endThisYear);
    }

    // Window crosses New Year, e.g. Dec 27 → Jan 7.
    if (today.month >= startThisYear.month) {
      final endNextYear = parseMonthDay(end, date.year + 1)!;
      return !today.isBefore(startThisYear) && !today.isAfter(endNextYear);
    }
    final startPreviousYear = parseMonthDay(start, date.year - 1)!;
    return !today.isBefore(startPreviousYear) && !today.isAfter(endThisYear);
  }

  static String? _url(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme != 'https') return null;
    return trimmed;
  }

  factory OnlineTheme.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'] ?? json['title'];
    if (id is! String || id.trim().isEmpty || name is! String || name.trim().isEmpty) {
      throw const FormatException('Invalid theme identity');
    }

    final rawPalette = json['palette'];
    final rawSeasonal = json['seasonal'];
    final palette = rawPalette is Map
        ? rawPalette.map((key, value) => MapEntry(key.toString(), value.toString()))
        : <String, String>{};

    return OnlineTheme(
      id: id.trim(),
      name: name.trim(),
      story: json['story'] is String ? (json['story'] as String).trim() : '',
      scene: json['scene'] is String ? (json['scene'] as String).trim() : 'mountain_lake',
      version: (json['version'] as num?)?.toInt() ?? 1,
      overlay: ((json['overlay'] as num?)?.toDouble() ?? 0.38).clamp(0.0, 1.0),
      palette: Map<String, String>.from(palette),
      previewUrl: _url(json['previewUrl']),
      // `imageUrl` is accepted as a backwards/portable alias for a full
      // wallpaper image. This matches the backend's documented image contract.
      wallpaperUrl: _url(json['wallpaperUrl']) ?? _url(json['imageUrl']),
      seasonal: rawSeasonal is Map
          ? Map<String, dynamic>.from(rawSeasonal.cast<String, dynamic>())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'story': story,
        'scene': scene,
        'version': version,
        'overlay': overlay,
        'palette': palette,
        if (previewUrl != null) 'previewUrl': previewUrl,
        if (wallpaperUrl != null) 'wallpaperUrl': wallpaperUrl,
        if (seasonal != null) 'seasonal': seasonal,
      };
}

class OnlineThemeService {
  OnlineThemeService._();

  static const _catalogUrl = Environment.themesUrl;

  static Future<List<OnlineTheme>> fetchCatalog() async {
    try {
      final response = await AppHttpClient.instance.client
          .get(
            Uri.parse(_catalogUrl),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        throw const FormatException('Theme catalog unavailable');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid theme catalog');
      }
      final rawItems = decoded['themes'];
      if (rawItems is! List) return const [];

      final themes = <OnlineTheme>[];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        try {
          themes.add(OnlineTheme.fromJson(Map<String, dynamic>.from(raw)));
        } catch (e) {
          debugPrint('[OnlineThemeService] Ignoring invalid theme: $e');
        }
      }
      return List<OnlineTheme>.unmodifiable(themes);
    } catch (e) {
      debugPrint('[OnlineThemeService] Catalog fetch failed: $e');
      throw const FormatException('Story themes are unavailable right now');
    }
  }

  static OnlineTheme? activeSeasonalTheme(
    List<OnlineTheme> themes, {
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final active = themes
        .where((theme) => theme.isSeasonal && theme.autoApply && theme.isActiveOn(date))
        .toList()
      ..sort((a, b) => b.seasonalPriority.compareTo(a.seasonalPriority));
    return active.isEmpty ? null : active.first;
  }
}
