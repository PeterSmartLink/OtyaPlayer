from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'{path}: expected source not found')
    file.write_text(text.replace(old, new, 1))


# 1) One gesture owner: tap-to-show controls and brightness/volume swipes must
# share the same detector. An invisible overlay must never consume the first
# swipe merely to reveal controls.
gesture_path = Path('lib/features/player/presentation/widgets/video_gesture_layer.dart')
gesture = gesture_path.read_text()
gesture = gesture.replace(
    '  final void Function(Duration delta)? onSeek;\n\n  const VideoGestureLayer({\n    super.key,\n    required this.child,\n    this.onSeek,\n  });',
    '  final void Function(Duration delta)? onSeek;\n  final VoidCallback? onTap;\n\n  const VideoGestureLayer({\n    super.key,\n    required this.child,\n    this.onSeek,\n    this.onTap,\n  });',
    1,
)
gesture = gesture.replace(
    '            behavior: HitTestBehavior.translucent,\n            onDoubleTapDown:',
    '            behavior: HitTestBehavior.translucent,\n            onTap: widget.onTap,\n            onDoubleTapDown:',
    1,
)
if 'final VoidCallback? onTap;' not in gesture or 'onTap: widget.onTap' not in gesture:
    raise SystemExit('gesture owner migration failed')
gesture_path.write_text(gesture)

player_path = Path('lib/features/player/presentation/video_player_screen.dart')
player = player_path.read_text()
player = player.replace(
    '          VideoGestureLayer(\n            onSeek:',
    '          VideoGestureLayer(\n            onTap: _resetHideTimer,\n            onSeek:',
    1,
)
block = '''          if (!_controlsVisible && !_isLocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _resetHideTimer,
                child: const SizedBox.expand(),
              ),
            ),
'''
if block not in player:
    raise SystemExit('hidden-controls gesture blocker did not match')
player = player.replace(block, '', 1)
if 'onTap: _resetHideTimer' not in player:
    raise SystemExit('player tap migration failed')
player_path.write_text(player)

# 2) The in-app browser must recognize the exact first-party topology used by
# the production router. Never wildcard all subdomains; keep a narrow allowlist.
webview_path = Path('lib/features/webview/otya_webview_screen.dart')
webview = webview_path.read_text()
webview = webview.replace(
    "  static const _trustedHosts = <String>{\n    'petersmartlink.com',\n    'www.petersmartlink.com',\n  };",
    "  static const _trustedHosts = <String>{\n    'petersmartlink.com',\n    'www.petersmartlink.com',\n    'space.petersmartlink.com',\n    'docs.petersmartlink.com',\n    'status.petersmartlink.com',\n  };",
    1,
)
webview = webview.replace(
    "    final binary = path.endsWith('.apk') ||\n        path.endsWith('.zip') ||\n        path.endsWith('.exe') ||\n        path.endsWith('.dmg');",
    "    final binary = path.endsWith('.apk') ||\n        path.endsWith('.zip') ||\n        path.endsWith('.exe') ||\n        path.endsWith('.dmg') ||\n        path == '/apk' ||\n        path.startsWith('/apk/');",
    1,
)
if 'space.petersmartlink.com' not in webview or "path.startsWith('/apk/')" not in webview:
    raise SystemExit('webview trust migration failed')
webview_path.write_text(webview)

# 3) One canonical release authority. The direct APK build reads /latest and
# requires an explicitly published immutable tag that agrees with version and
# build number. Play builds do not sideload from PeterSmart Link.
update_service = r'''import 'dart:convert';

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
'''
Path('lib/core/services/update_service.dart').write_text(update_service)

# Update prompt: first-party HTML stays inside Otya. The WebView itself hands
# /apk/... binary navigation to Android/the external browser.
update_dialog_path = Path('lib/core/widgets/update_dialog.dart')
update_dialog = update_dialog_path.read_text()
if "package:go_router/go_router.dart" not in update_dialog:
    update_dialog = update_dialog.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\nimport 'package:go_router/go_router.dart';\n",
        1,
    )
start = update_dialog.index('  Future<void> _openOfficialUpdate() async {')
end = update_dialog.index('\n  Future<void> _later()', start)
new_open = '''  Future<void> _openOfficialUpdate() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });

    final uri = Uri.tryParse(widget.info.downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !_officialHosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = 'Otya could not verify the official update address.';
        });
      }
      return;
    }

    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    router.push(
      '/webview',
      extra: {'url': uri.toString(), 'title': 'Update Otya'},
    );
  }
'''
update_dialog = update_dialog[:start] + new_open + update_dialog[end:]
update_dialog = update_dialog.replace(
    "              'Otya will open the official PeterSmart Link update destination. '\n              'The app does not silently install packages or require installer permission.',",
    "              'Otya opens the official PeterSmart Link update page inside the app. '\n              'When you choose the APK, Android handles the download/install step; Otya never silently installs packages.',",
    1,
)
update_dialog = update_dialog.replace(
    "          label: Text(_opening ? 'Opening…' : 'Update'),",
    "          label: Text(_opening ? 'Opening…' : 'View update'),",
    1,
)
update_dialog_path.write_text(update_dialog)

# Manual surfaces must never say "up to date" when the release service failed,
# is pre-release, or this build is Play-managed.
about_path = Path('lib/features/settings/presentation/about_screen.dart')
about = about_path.read_text()
old = '''      if (info == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Otya is up to date.')),
        );
      } else {
        await UpdateDialog.checkAndShow(context);
      }
'''
new = '''      if (info == null) {
        final service = UpdateService.instance;
        final message = switch (service.lastState) {
          UpdateCheckState.current => 'Otya is up to date.',
          UpdateCheckState.preRelease =>
            'No public Otya release is published yet.',
          UpdateCheckState.skipped =>
            service.lastError ?? 'The update check was skipped.',
          UpdateCheckState.unavailable =>
            service.lastError ?? 'The Otya release service is unavailable.',
          _ => service.lastError ?? 'No update information is available.',
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
      } else {
        await UpdateDialog.checkAndShow(context, forceCheck: true);
      }
'''
if old not in about:
    raise SystemExit('about update state block did not match')
about_path.write_text(about.replace(old, new, 1))

whats_path = Path('lib/features/profile/whats_new_screen.dart')
whats = whats_path.read_text()
old = '''      setState(() {
        _text = info == null || info.changelog.isEmpty
            ? 'You have the latest available version.'
            : info.changelog;
      });
'''
new = '''      final service = UpdateService.instance;
      setState(() {
        if (info != null && info.changelog.isNotEmpty) {
          _text = info.changelog;
        } else if (service.lastState == UpdateCheckState.current) {
          _text = 'You have the latest published Otya build.';
        } else {
          _text = service.lastError ?? 'No published release notes are available.';
        }
      });
'''
if old not in whats:
    raise SystemExit("what's new state block did not match")
whats_path.write_text(whats.replace(old, new, 1))

# 4) Clean the strict-analyzer failures already found by CI.
offline_path = Path('test/offline_send_hotspot_contract_test.dart')
offline = offline_path.read_text()
offline = offline.replace('contains("\'Offline network\'")', 'contains("\'Offline network\'")')
offline = offline.replace('contains("Received/$folder")', "contains(r'Received/$folder')")
offline_path.write_text(offline)

ambient_path = Path('test/together_ambient_overlay_contract_test.dart')
ambient = ambient_path.read_text().replace(
    'contains("together_ambient_overlay.dart")',
    "contains('together_ambient_overlay.dart')",
)
ambient_path.write_text(ambient)

widgets_path = Path('lib/features/video/presentation/widgets/video_tab_widgets.dart')
widgets = widgets_path.read_text()
widgets, card_count = re.subn(
    r'\nclass _VideoCard extends StatelessWidget \{.*?\nclass _FolderCard extends StatelessWidget \{',
    '\nclass _FolderCard extends StatelessWidget {',
    widgets,
    count=1,
    flags=re.S,
)
widgets, grid_count = re.subn(
    r'\nint _gridColumns\(double width\) \{.*?\n\}\n\nString _folderName',
    '\nString _folderName',
    widgets,
    count=1,
    flags=re.S,
)
if card_count != 1 or grid_count != 1:
    raise SystemExit(f'dead video cleanup mismatch card={card_count} grid={grid_count}')
widgets_path.write_text(widgets)

# Update the older stabilization contract to require truthful Play/direct update
# policy rather than forbidding the policy entirely.
stab_path = Path('test/production_stabilization_contract_test.dart')
stab = stab_path.read_text()
stab = stab.replace(
    "    expectNotContains(updates, 'if (!Environment.selfUpdateEnabled) return null;');\n    expect(updates, contains('UpdateCheckState.unavailable'));",
    "    expect(updates, contains('if (!Environment.selfUpdateEnabled) {'));\n    expect(updates, contains('Updates for this build are managed by Google Play.'));\n    expect(updates, contains('UpdateCheckState.unavailable'));",
    1,
)
stab_path.write_text(stab)

# Whole-system contract: guard the cross-feature seams that caused the visible
# bugs instead of testing each feature in isolation.
Path('test/system_truth_contract_test.dart').write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video uses one pointer owner for tap and swipe gestures', () {
    final player = File(
      'lib/features/player/presentation/video_player_screen.dart',
    ).readAsStringSync();
    final gestures = File(
      'lib/features/player/presentation/widgets/video_gesture_layer.dart',
    ).readAsStringSync();

    expect(player, contains('onTap: _resetHideTimer'));
    expect(gestures, contains('final VoidCallback? onTap;'));
    expect(gestures, contains('onTap: widget.onTap'));
    expect(
      player,
      isNot(contains("if (!_controlsVisible && !_isLocked)\n            Positioned.fill(")),
    );
  });

  test('in-app browser matches exact PeterSmart Link production surfaces', () {
    final browser = File(
      'lib/features/webview/otya_webview_screen.dart',
    ).readAsStringSync();

    for (final host in [
      'petersmartlink.com',
      'www.petersmartlink.com',
      'space.petersmartlink.com',
      'docs.petersmartlink.com',
      'status.petersmartlink.com',
    ]) {
      expect(browser, contains("'$host'"));
    }
    expect(browser, contains("path.startsWith('/apk/')"));
    expect(browser, contains('LaunchMode.externalApplication'));
  });

  test('direct updater accepts only one coherent published release identity', () {
    final updates = File('lib/core/services/update_service.dart').readAsStringSync();
    final dialog = File('lib/core/widgets/update_dialog.dart').readAsStringSync();

    expect(updates, contains("data['published'] != true"));
    expect(updates, contains("r'^v(\\d+\\.\\d+\\.\\d+)\\+([1-9]\\d*)\$'"));
    expect(updates, contains('tagMatch.group(1) != serverVersion'));
    expect(updates, contains('tagBuild != serverVersionCode'));
    expect(updates, contains("final exactKey = abi == 'arm64' ? 'exactArm64' : 'exactArm32'"));
    expect(updates, contains('Updates for this build are managed by Google Play.'));
    expect(dialog, contains("router.push(\n      '/webview'"));
    expect(dialog, isNot(contains('LaunchMode.externalApplication')));
  });
}
''')

print('system truth pass applied')
