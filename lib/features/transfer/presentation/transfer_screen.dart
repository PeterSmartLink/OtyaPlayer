import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:otya_transfer_android/otya_transfer_android.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/storage_folder_service.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../air_drop/data/media_receiver.dart';
import '../../air_drop/data/media_sender.dart';
import '../../my_space/data/media_repository.dart';
import '../../my_space/presentation/providers/my_space_provider.dart';
import '../data/transfer_hotspot_service.dart';

enum _TransferMode { send, receive }
enum _TransferMediaKind { videos, music }

/// Otya's contextual nearby sharing surface.
///
/// This deliberately avoids exposing transport terms such as "offline mode".
/// The user chooses Send or Receive, Otya prepares a direct connection, and
/// videos/music stay visually separated instead of becoming one mixed file list.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final MediaSender _sender = MediaSender();
  final MediaReceiver _receiver = MediaReceiver();
  final MobileScannerController _scanner = MobileScannerController();
  final TransferHotspotService _hotspot = TransferHotspotService.instance;

  _TransferMode _mode = _TransferMode.send;
  _TransferMediaKind _mediaKind = _TransferMediaKind.videos;
  MediaItem? _selected;
  OtyaHotspotInfo? _hotspotInfo;
  String? _shareUrl;
  String? _receivedPath;
  String? _error;
  double _progress = 0;
  bool _sending = false;
  bool _receiving = false;
  bool _scanLocked = false;
  bool _connectionReady = false;
  bool _preparingConnection = false;
  bool _ownsHotspot = false;

  @override
  void dispose() {
    _sender.stop();
    _receiver.cancel();
    _scanner.stop();
    _scanner.dispose();
    if (_ownsHotspot) _hotspot.stop();
    super.dispose();
  }

  Future<void> _stopOwnedHotspot() async {
    if (!_ownsHotspot) return;
    await _hotspot.stop();
    _ownsHotspot = false;
    _hotspotInfo = null;
  }

  void _switchMode(_TransferMode mode) {
    HapticFeedback.selectionClick();
    if (_mode == mode) return;
    unawaited(_sender.stop());
    _receiver.cancel();
    if (_ownsHotspot) unawaited(_stopOwnedHotspot());
    setState(() {
      _mode = mode;
      _shareUrl = null;
      _receivedPath = null;
      _error = null;
      _progress = 0;
      _sending = false;
      _receiving = false;
      _scanLocked = false;
      _connectionReady = false;
      _preparingConnection = false;
      _selected = null;
      _hotspotInfo = null;
    });
  }

  Future<void> _useCurrentWifi() async {
    if (_preparingConnection) return;
    HapticFeedback.selectionClick();
    setState(() {
      _preparingConnection = true;
      _error = null;
    });
    try {
      final allowed = await _hotspot.ensureLocalNetworkAccess();
      if (!mounted) return;
      if (!allowed) {
        setState(() => _error =
            'Allow Nearby devices so Otya can connect to the other phone.');
        return;
      }
      setState(() {
        _connectionReady = true;
        _hotspotInfo = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Otya could not prepare the connection.');
      }
    } finally {
      if (mounted) setState(() => _preparingConnection = false);
    }
  }

  Future<void> _createHotspot() async {
    if (_preparingConnection) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _preparingConnection = true;
      _error = null;
    });
    try {
      final info = _hotspot.active ?? await _hotspot.start();
      if (!mounted || info == null) return;
      setState(() {
        _ownsHotspot = true;
        _hotspotInfo = info;
        _connectionReady = true;
      });
    } on TransferHotspotException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Android could not create the hotspot.');
      }
    } finally {
      if (mounted) setState(() => _preparingConnection = false);
    }
  }

  Future<void> _changeConnection() async {
    await _sender.stop();
    if (_ownsHotspot) await _stopOwnedHotspot();
    if (!mounted) return;
    setState(() {
      _connectionReady = false;
      _shareUrl = null;
      _selected = null;
      _error = null;
      _hotspotInfo = null;
    });
  }

  Future<void> _send(MediaItem item) async {
    if (_sending || !_connectionReady) return;
    HapticFeedback.lightImpact();
    await _sender.stop();
    if (!mounted) return;
    setState(() {
      _selected = item;
      _sending = true;
      _shareUrl = null;
      _error = null;
    });
    try {
      final url = await _sender.startServing(item.filePath);
      if (!mounted) return;
      setState(() => _shareUrl = url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Could not start sending. Check the connection between both phones and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Directory> _receiveDirectory(String fileName) async {
    final type = _mediaKindForName(fileName);
    final folder = type == _TransferMediaKind.videos ? 'Videos' : 'Music';
    try {
      final root = await StorageFolderService.instance.publicRoot;
      final dir = Directory('${root.path}/Received/$folder');
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      final root = await StorageFolderService.instance.privateRoot;
      final dir = Directory('${root.path}/Received/$folder');
      await dir.create(recursive: true);
      return dir;
    }
  }

  Future<void> _receive(String rawUrl) async {
    if (_receiving) return;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'http' || !_isPrivateHost(uri.host)) {
      setState(() {
        _error = 'That code is not a valid Otya Send connection.';
        _scanLocked = false;
      });
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _receiving = true;
      _error = null;
      _receivedPath = null;
      _progress = 0;
    });

    try {
      final advertised = uri.queryParameters['name']
          ?.replaceAll('\\', '/')
          .split('/')
          .last
          .replaceAll(RegExp(r'[\x00-\x1F]'), '')
          .trim();
      final fileName = advertised != null && advertised.isNotEmpty
          ? advertised
          : 'received_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final dir = await _receiveDirectory(fileName);

      final file = await _receiver.download(
        url: rawUrl,
        savePath: '${dir.path}/$fileName',
        onProgress: (downloaded, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0
                ? (downloaded / total).clamp(0.0, 1.0)
                : 0;
          });
        },
      );

      MediaRepository.instance.invalidate();
      await ref.read(mediaLibraryProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _receivedPath = file.path;
        _progress = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'The transfer did not finish. Keep both phones connected and try again.');
    } finally {
      if (mounted) {
        setState(() {
          _receiving = false;
          _scanLocked = false;
        });
      }
    }
  }

  _TransferMediaKind _mediaKindForName(String name) {
    final lower = name.toLowerCase();
    const videos = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.ts'};
    return videos.any(lower.endsWith)
        ? _TransferMediaKind.videos
        : _TransferMediaKind.music;
  }

  bool _isPrivateHost(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    return a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  @override
  Widget build(BuildContext context) {
    final library =
        ref.watch(mediaLibraryProvider).valueOrNull ?? const <MediaItem>[];
    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(_mode == _TransferMode.send ? 'Send' : 'Receive'),
        actions: [
          if (_connectionReady)
            IconButton(
              tooltip: 'Change connection',
              onPressed: _changeConnection,
              icon: const Icon(Icons.wifi_find_rounded),
            ),
          if (_shareUrl != null)
            TextButton(
              onPressed: () {
                _sender.stop();
                setState(() => _shareUrl = null);
              },
              child: const Text('Stop'),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: _ModeSwitch(mode: _mode, onChanged: _switchMode),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _mode == _TransferMode.send
                    ? _sendBody(context, library)
                    : _receiveBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendBody(BuildContext context, List<MediaItem> library) {
    if (!_connectionReady) {
      return _ConnectionSetup(
        key: const ValueKey('send-connection'),
        title: 'Connect the two phones',
        subtitle:
            'Create a hotspot here, or use Wi-Fi both phones are already connected to.',
        busy: _preparingConnection,
        error: _error,
        primaryLabel: 'Create hotspot',
        primaryIcon: Icons.wifi_tethering_rounded,
        onPrimary: _createHotspot,
        secondaryLabel: 'Use current Wi-Fi',
        secondaryIcon: Icons.wifi_rounded,
        onSecondary: _useCurrentWifi,
      );
    }

    if (_shareUrl != null && _selected != null) {
      return ListView(
        key: const ValueKey('send-ready'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (_hotspotInfo != null) ...[
            _HotspotDetails(info: _hotspotInfo!),
            const SizedBox(height: 18),
          ],
          Text(
            'Ready to send',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -.6,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Open Receive on the other phone and scan this code.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: .18),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: QrImageView(
                data: _shareUrl!,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _selected!.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${_selected!.isVideo ? 'Video' : 'Music'} · ${_selected!.formattedSize}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _shareUrl!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Send link copied')),
              );
            },
            icon: const Icon(Icons.content_copy_rounded),
            label: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () {
              _sender.stop();
              setState(() {
                _shareUrl = null;
                _selected = null;
              });
            },
            child: const Text('Choose another'),
          ),
        ],
      );
    }

    final filtered = library
        .where((item) =>
            _mediaKind == _TransferMediaKind.videos ? item.isVideo : !item.isVideo)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return ListView(
      key: const ValueKey('send-picker'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
      children: [
        if (_hotspotInfo != null) ...[
          _HotspotDetails(info: _hotspotInfo!),
          const SizedBox(height: 16),
        ],
        Text(
          'Choose what to send',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -.4,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Videos and music stay separate so your library remains easy to scan.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        _MediaKindSwitch(
          value: _mediaKind,
          onChanged: (value) {
            HapticFeedback.selectionClick();
            setState(() => _mediaKind = value);
          },
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          _ErrorCard(message: _error!),
          const SizedBox(height: 10),
        ],
        if (filtered.isEmpty)
          _EmptyTransfer(
            icon: _mediaKind == _TransferMediaKind.videos
                ? Icons.video_library_outlined
                : Icons.library_music_outlined,
            title: _mediaKind == _TransferMediaKind.videos
                ? 'No videos found'
                : 'No music found',
            subtitle: 'Add media to your device and refresh your library.',
          )
        else
          ...filtered.map(
            (item) => _MediaRow(
              item: item,
              busy: _sending && _selected?.id == item.id,
              onTap: _sending ? null : () => _send(item),
            ),
          ),
      ],
    );
  }

  Widget _receiveBody(BuildContext context) {
    if (!_connectionReady) {
      return _ConnectionSetup(
        key: const ValueKey('receive-connection'),
        title: 'Connect to the sender',
        subtitle:
            'Join the hotspot shown by the sender, or connect both phones to the same Wi-Fi. Then continue to the scanner.',
        busy: _preparingConnection,
        error: _error,
        primaryLabel: 'I’m connected',
        primaryIcon: Icons.link_rounded,
        onPrimary: _useCurrentWifi,
      );
    }

    if (_receivedPath != null) {
      final name = _receivedPath!.replaceAll('\\', '/').split('/').last;
      final kind = _mediaKindForName(name);
      return _ResultView(
        key: const ValueKey('receive-done'),
        icon: Icons.check_circle_rounded,
        title: kind == _TransferMediaKind.videos
            ? 'Video received'
            : 'Music received',
        subtitle: '$name\nSaved in Otya → Received → '
            '${kind == _TransferMediaKind.videos ? 'Videos' : 'Music'}.',
        action: 'Receive another',
        onAction: () => setState(() {
          _receivedPath = null;
          _error = null;
          _progress = 0;
          _scanLocked = false;
        }),
      );
    }

    if (_receiving) {
      return ListView(
        key: const ValueKey('receiving'),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(
            Icons.downloading_rounded,
            size: 62,
            color: AppColors.brandCyan,
          ),
          const SizedBox(height: 20),
          const Text(
            'Receiving',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 22),
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 7,
          ),
          const SizedBox(height: 10),
          Text(
            _progress > 0
                ? '${(_progress * 100).toStringAsFixed(0)}%'
                : 'Connecting…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () {
              _receiver.cancel();
              setState(() {
                _receiving = false;
                _progress = 0;
                _scanLocked = false;
              });
            },
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    return ListView(
      key: const ValueKey('receive-scan'),
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan the sender',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Point the camera at the Send QR code.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _changeConnection,
              child: const Text('Connection'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_error != null) ...[
          _ErrorCard(message: _error!),
          const SizedBox(height: 12),
        ],
        Center(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: AppColors.brandCyan.withValues(alpha: .34),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: .16),
                  blurRadius: 28,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 286,
                height: 286,
                child: MobileScanner(
                  controller: _scanner,
                  fit: BoxFit.cover,
                  onDetect: (capture) {
                    if (_scanLocked || capture.barcodes.isEmpty) return;
                    final value = capture.barcodes.first.rawValue ??
                        capture.barcodes.first.displayValue;
                    if (value == null || !value.startsWith('http://')) return;
                    _scanLocked = true;
                    _receive(value);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionSetup extends StatelessWidget {
  const _ConnectionSetup({
    super.key,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
    this.error,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;
  final String? error;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradientDiag,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: .24),
                  blurRadius: 28,
                ),
              ],
            ),
            child: Icon(
              primaryIcon,
              size: 34,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 18),
            _ErrorCard(message: error!),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onPrimary,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(primaryIcon),
              label: Text(primaryLabel),
            ),
          ),
          if (onSecondary != null && secondaryLabel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSecondary,
                icon: Icon(secondaryIcon ?? Icons.wifi_rounded),
                label: Text(secondaryLabel!),
              ),
            ),
          ],
        ],
      );
}

class _HotspotDetails extends StatelessWidget {
  const _HotspotDetails({required this.info});

  final OtyaHotspotInfo info;

  @override
  Widget build(BuildContext context) {
    final password = info.passphrase?.trim();
    final hasPassword = password != null && password.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.brandCyan.withValues(alpha: .20),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: info.wifiQrPayload,
              size: 74,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hotspot ready',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  info.ssid,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasPassword)
                  SelectableText(
                    password,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy hotspot details',
            onPressed: () {
              final text = hasPassword
                  ? 'Otya\nNetwork: ${info.ssid}\nPassword: $password'
                  : 'Otya\nNetwork: ${info.ssid}';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hotspot details copied')),
              );
            },
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _MediaKindSwitch extends StatelessWidget {
  const _MediaKindSwitch({required this.value, required this.onChanged});

  final _TransferMediaKind value;
  final ValueChanged<_TransferMediaKind> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            _KindButton(
              label: 'Videos',
              icon: Icons.video_library_rounded,
              active: value == _TransferMediaKind.videos,
              onTap: () => onChanged(_TransferMediaKind.videos),
            ),
            _KindButton(
              label: 'Music',
              icon: Icons.library_music_rounded,
              active: value == _TransferMediaKind.music,
              onTap: () => onChanged(_TransferMediaKind.music),
            ),
          ],
        ),
      );
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.item, required this.busy, required this.onTap});

  final MediaItem item;
  final bool busy;
  final VoidCallback? onTap;

  String _folder(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.length > 1 ? parts[parts.length - 2] : 'Device';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.brandBlue.withValues(alpha: .20),
                          AppColors.brandCyan.withValues(alpha: .09),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      item.isVideo
                          ? Icons.play_circle_fill_rounded
                          : Icons.music_note_rounded,
                      color: AppColors.brandCyan,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.isVideo
                              ? '${_folder(item.filePath)} · ${item.formattedDuration} · ${item.formattedSize}'
                              : '${item.artist ?? _folder(item.filePath)} · ${item.formattedSize}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (busy)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final _TransferMode mode;
  final ValueChanged<_TransferMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            _ModeButton(
              label: 'Send',
              icon: Icons.north_east_rounded,
              active: mode == _TransferMode.send,
              onTap: () => onChanged(_TransferMode.send),
            ),
            _ModeButton(
              label: 'Receive',
              icon: Icons.south_west_rounded,
              active: mode == _TransferMode.receive,
              onTap: () => onChanged(_TransferMode.receive),
            ),
          ],
        ),
      );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: active ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _KindButton extends _ModeButton {
  const _KindButton({
    required super.label,
    required super.icon,
    required super.active,
    required super.onTap,
  });
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withValues(alpha: .22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _EmptyTransfer extends StatelessWidget {
  const _EmptyTransfer({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 66, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 50, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: AppColors.accentGreen),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(action)),
            ],
          ),
        ),
      );
}
