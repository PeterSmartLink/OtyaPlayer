import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/environment.dart';
import 'api_signer.dart';
import 'device_service.dart';
import 'firebase_platform_service.dart';

/// Handles Rate Us and Report a Problem.
/// Data is posted to the PeterSmart Link backend and the email client is also
/// opened as a fallback — both are fire-and-forget.
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  static const String _prefRatePromptKey = 'rate_prompt_shown_version';

  PackageInfo? _cachedPkg;
  SharedPreferences? _cachedPrefs;

  Future<PackageInfo> _pkg() async =>
      _cachedPkg ??= await PackageInfo.fromPlatform();

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  Future<Map<String, String>> _deviceInfo() async {
    final pkg = await _pkg();
    final deviceId = await DeviceService.instance.getDeviceId();
    return {
      'version': pkg.version,
      'buildNumber': pkg.buildNumber,
      'deviceId': deviceId,
    };
  }

  Future<bool> _hasConnection() async {
    try {
      final result = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      if (result.contains(ConnectivityResult.none)) return false;
      final probe = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      return probe.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<void> _postToWorker(
    String path,
    Map<String, dynamic> data,
    String deviceId,
  ) async {
    try {
      final headers = await FirebasePlatformService.instance.protectedHeaders(
        base: {
          ...ApiSigner.signedHeaders(
            method: 'POST',
            path: path,
            deviceId: deviceId,
          ),
          'Content-Type': 'application/json',
        },
      );
      final res = await http
          .post(
            Uri.parse('${Environment.workerUrl}$path'),
            headers: headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) {
        debugPrint(
          '[FeedbackService] Worker $path HTTP ${res.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[FeedbackService] Worker post failed (non-fatal): $e');
    }
  }

  Future<void> _openEmail(String subject, String body) async {
    final uri = Uri(
      scheme: 'mailto',
      path: Environment.supportEmail,
      queryParameters: {'subject': subject, 'body': body},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('[FeedbackService] Could not open mail app.');
    }
  }

  Future<bool> shouldShowRatePrompt() async {
    if (!await _hasConnection()) return false;
    final pkg = await _pkg();
    final prefs = await _prefs();
    return (prefs.getString(_prefRatePromptKey) ?? '') != pkg.version;
  }

  Future<void> markRatePromptShown() async {
    final pkg = await _pkg();
    final prefs = await _prefs();
    await prefs.setString(_prefRatePromptKey, pkg.version);
  }

  Future<void> submitRating({
    required int stars,
    required String comment,
  }) async {
    final info = await _deviceInfo();

    _postToWorker('/api/ratings', {
      'device_id': info['deviceId'],
      'app_version': info['version'],
      'version_code': int.tryParse(info['buildNumber']!) ?? 0,
      'stars': stars.clamp(1, 5),
      'comment': comment.trim(),
    }, info['deviceId']!).ignore();

    final starEmoji = List.filled(stars.clamp(1, 5), '⭐').join();
    final subject = 'Otya Rating — ${stars.clamp(1, 5)} stars';
    final body =
        'Stars: $starEmoji (${stars.clamp(1, 5)}/5)\n'
        '${comment.trim().isNotEmpty ? 'Comment: ${comment.trim()}\n' : ''}\n'
        'App version: ${info['version']} (${info['buildNumber']})\n'
        'Device ID: ${info['deviceId']}';

    await _openEmail(subject, body);
  }

  Future<void> submitReport({
    required String description,
    required String category,
    String? userEmail,
  }) async {
    final info = await _deviceInfo();
    final cleanDescription = description.trim();
    final cleanCategory = category.trim().isEmpty ? 'other' : category.trim();
    final cleanEmail = userEmail?.trim();

    _postToWorker('/api/feedback', {
      'device_id': info['deviceId'],
      'app_version': info['version'],
      'version_code': int.tryParse(info['buildNumber']!) ?? 0,
      'category': cleanCategory,
      'description': cleanDescription,
      if (cleanEmail != null && cleanEmail.isNotEmpty) 'user_email': cleanEmail,
    }, info['deviceId']!).ignore();

    final categoryLabel = cleanCategory[0].toUpperCase() + cleanCategory.substring(1);
    final subject = 'Otya Problem Report — $categoryLabel';
    final body =
        'Category: $categoryLabel\n'
        'Description: $cleanDescription\n\n'
        'App version: ${info['version']} (${info['buildNumber']})\n'
        'Device ID: ${info['deviceId']}'
        '${cleanEmail != null && cleanEmail.isNotEmpty ? '\nUser email: $cleanEmail' : ''}';

    await _openEmail(subject, body);
  }
}
