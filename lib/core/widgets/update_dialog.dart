import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/environment.dart';

import '../../shared/widgets/otya_logo.dart';
import '../services/update_service.dart';
import '../services/update_download_status.dart';

/// Download official direct-install updates without opening a web page.
/// Android manages the background download and asks the user to install it.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});
  final UpdateInfo info;

  static bool _showing = false;

  static Future<void> checkAndShow(
    BuildContext context, {
    bool forceCheck = false,
  }) async {
    if (_showing) return;

    final update = await UpdateService.instance.checkForUpdate(force: forceCheck);
    if (update == null || !context.mounted) {
      if (forceCheck && context.mounted) {
        final service = UpdateService.instance;
        final message = service.lastState == UpdateCheckState.current
            ? 'Otya is up to date.'
            : service.lastError ?? 'Could not check for updates. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return;
    }

    if (_showing || !context.mounted) return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !updateIsMandatory(update),
        builder: (_) => UpdateDialog(info: update),
      );
    } finally {
      _showing = false;
    }
  }

  // Minimum-version policy is enforced at online-service boundaries. Otya
  // never blocks a user's local media library behind an internet update.
  static bool updateIsMandatory(UpdateInfo info) => false;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  static const _officialHosts = <String>{
    'petersmartlink.com',
    'www.petersmartlink.com',
  };

  static const _downloads = MethodChannel('com.otyaplayer.app/updates');
  bool _downloadStarted = false;
  UpdateDownloadStatus _status = const UpdateDownloadStatus();
  Timer? _statusTimer;
  bool _polling = false;
  int _statusGeneration = 0;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Environment.selfUpdateEnabled) _startStatusUpdates();
  }

  void _startStatusUpdates() {
    _statusTimer?.cancel();
    unawaited(_refreshStatus());
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_status.isActive) unawaited(_refreshStatus());
    });
  }

  Future<void> _refreshStatus() async {
    if (_polling || _opening || !mounted) return;
    _polling = true;
    final generation = _statusGeneration;
    try {
      final result = await _downloads.invokeMapMethod<Object?, Object?>(
        'status', {'tag': widget.info.tag},
      );
      if (!mounted || generation != _statusGeneration || result == null) return;
      final status = UpdateDownloadStatus.fromMap(result);
      setState(() {
        _status = status;
        _downloadStarted = status.isActive || status.isComplete;
      });
    } catch (_) {
      // Keep the previous state; a status-query error is not download failure.
    } finally {
      _polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Environment.selfUpdateEnabled) return;
    if (state == AppLifecycleState.resumed) {
      _startStatusUpdates();
    } else {
      _statusTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _openOfficialUpdate() async {
    if (_opening) return;
    _statusGeneration++;
    setState(() {
      _opening = true;
      _error = null;
    });

    final uri = Uri.tryParse(widget.info.directUrl);
    if (!Environment.selfUpdateEnabled ||
        uri == null ||
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

    try {
      if (_downloadStarted) {
        await _downloads.invokeMethod<void>('showDownloads');
      } else {
        final id = await _downloads.invokeMethod<int>('download', {
          'url': uri.toString(),
          'tag': widget.info.tag,
        });
        if (id == null) throw StateError('Download was not accepted');
        if (mounted) {
          setState(() {
            _downloadStarted = true;
            _status = const UpdateDownloadStatus(status: 'pending');
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The update download could not be opened. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        unawaited(_refreshStatus());
      }
    }
  }

  Future<void> _later() async {
    await UpdateService.instance.remindLater(widget.info.versionCode);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = widget.info.changelog.trim();

    return AlertDialog(
      scrollable: true,
      icon: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const OtyaMark(size: 46),
      ),
      title: Text('Otya ${widget.info.version} is available'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Installed build ${widget.info.installedCode} · available build ${widget.info.versionCode}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                "What's new",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(notes, style: const TextStyle(height: 1.45)),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_status.label.isNotEmpty) ...[
              Text(_status.label, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 10),
              if (_status.isActive)
                LinearProgressIndicator(value: _status.progress),
              const SizedBox(height: 10),
            ],
            Text(
              _downloadStarted
                  ? 'Your download is managed by Android and can continue in the background. '
                      'When it finishes, tap its notification to open the update.'
                  : 'Download the update here, then approve installation in Android. '
                      'Otya never silently installs packages.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _opening ? null : _later,
          child: Text(_downloadStarted ? 'Close' : 'Later'),
        ),
        FilledButton.icon(
          onPressed: _opening ? null : _openOfficialUpdate,
          icon: _opening
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_opening
              ? 'Opening…'
              : _status.canRetry
                  ? 'Retry download'
                  : _downloadStarted ? 'View download' : 'Download update'),
        ),
      ],
    );
  }
}
