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
import '../../my_space/data/media_repository.dart';
import '../../my_space/presentation/providers/my_space_provider.dart';
import '../data/media_receiver.dart';
import '../data/media_sender.dart';
import '../data/transfer_hotspot_service.dart';
import '../data/transfer_security_policy.dart';

enum _TransferMode { send, receive }
enum _TransferMediaKind { videos, music }

/// Otya's contextual nearby sharing surface.
///
/// Send and Receive stay one lightweight flow. Selection is deliberately
/// multi-item: users can choose several videos, switch to Music, add several
/// songs, then share the whole batch with one QR code. No cloud relay or ZIP
/// staging is required.
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
  final Map<String, MediaItem> _selectedMedia = <String, MediaItem>{};

  _TransferMode _mode = _TransferMode.send;
  _TransferMediaKind _mediaKind = _TransferMediaKind.videos;
  OtyaHotspotInfo? _hotspotInfo;
  String? _shareUrl;
  String? _lastReceivedPath;
  String? _error;
  double _progress = 0;
  bool _sending = false;
  bool _receiving = false;
  bool _scanLocked = false;
  bool _connectionReady = false;
  bool _preparingConnection = false;
  bool _ownsHotspot = false;
  bool _cancelRequested = false;
  int _receivedCount = 0;
  int _receiveItemIndex = 0;
  int _receiveItemCount = 0;

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
      _lastReceivedPath = null;
      _error = null;
      _progress = 0;
      _sending = false;
      _receiving = false;
      _scanLocked = false;
      _connectionReady = false;
      _preparingConnection = false;
      _hotspotInfo = null;
      _cancelRequested = false;
      _receivedCount = 0;
      _receiveItemIndex = 0;
      _receiveItemCount = 0;
      _selectedMedia.clear();
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
    _receiver.cancel();
    if (_ownsHotspot) await _stopOwnedHotspot();
    if (!mounted) return;
    setState(() {
      _connectionReady = false;
      _shareUrl = null;
      _lastReceivedPath = null;
      _error = null;
      _hotspotInfo = null;
      _progress = 0;
      _receivedCount = 0;
      _selectedMedia.clear();
    });
  }

  void _toggleSelection(MediaItem item) {
    if (_sending) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedMedia.containsKey(item.id)) {
        _selectedMedia.remove(item.id);
      } else {
        _selectedMedia[item.id] = item;
      }
      _error = null;
    });
  }

  void _toggleAllVisible(List<MediaItem> visible) {
    if (_sending || visible.isEmpty) return;
    HapticFeedback.selectionClick();
    final allSelected = visible.every((item) => _selectedMedia.containsKey(item.id));
    setState(() {
      if (allSelected) {
        for (final item in visible) {
          _selectedMedia.remove(item.id);
        }
      } else {
        for (final item in visible) {
          _selectedMedia[item.id] = item;
        }
      }
    });
  }

  Future<void> _sendSelected() async {
    if (_sending || !_connectionReady || _selectedMedia.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _sending = true;
      _shareUrl = null;
      _error = null;
    });
    try {
      final url = await _sender.startServingBatch(
        _selectedMedia.values.map((item) => item.filePath),
      );
      if (!mounted) return;
      setState(() => _shareUrl = url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Could not prepare this batch. Keep both phones connected and try again.');
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

  OtyaTransferBatchItem _legacySingleItem(Uri uri, String rawUrl) {
    final advertised = uri.queryParameters['name']
        ?.replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    final fileName = advertised != null && advertised.isNotEmpty
        ? advertised
        : 'received_${DateTime.now().millisecondsSinceEpoch}.mp4';
    return OtyaTransferBatchItem(name: fileName, url: rawUrl, sizeBytes: 0);
  }

  Future<void> _receive(String rawUrl) async {
    if (_receiving) return;
    final uri = Uri.tryParse(rawUrl);
    final isBatch = uri != null && isAllowedTransferBatchUri(uri);
    final isSingle = uri != null &&
        isAllowedTransferUri(uri) &&
        uri.path != '/together-stream';
    if (uri == null || (!isBatch && !isSingle)) {
      setState(() {
        _error = 'That code is not a valid Otya Send connection.';
        _scanLocked = false;
      });
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _receiving = true;
      _cancelRequested = false;
      _error = null;
      _lastReceivedPath = null;
      _receivedCount = 0;
      _receiveItemIndex = 0;
      _receiveItemCount = 0;
      _progress = 0;
    });

    try {
      final items = isBatch
          ? await _receiver.discoverBatch(rawUrl)
          : <OtyaTransferBatchItem>[_legacySingleItem(uri, rawUrl)];
      if (!mounted) return;
      setState(() => _receiveItemCount = items.length);

      final totalExpected = items.fold<int>(
        0,
        (sum, item) => sum + item.sizeBytes,
      );
      var completedExpected = 0;
      final received = <String>[];

      for (var index = 0; index < items.length; index++) {
        if (_cancelRequested) throw const TransferCancelledException();
        final item = items[index];
        final dir = await _receiveDirectory(item.name);
        if (!mounted) return;
        setState(() => _receiveItemIndex = index + 1);

        final file = await _receiver.download(
          url: item.url,
          savePath: '${dir.path}/${item.name}',
          onProgress: (downloaded, total) {
            if (!mounted) return;
            double nextProgress;
            if (totalExpected > 0 && item.sizeBytes > 0) {
              final current = downloaded.clamp(0, item.sizeBytes).toDouble();
              nextProgress = (completedExpected + current) / totalExpected;
            } else {
              final itemProgress = total > 0
                  ? (downloaded / total).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              nextProgress = (index + itemProgress) / items.length;
            }
            setState(() => _progress = nextProgress.clamp(0.0, 1.0).toDouble());
          },
        );
        received.add(file.path);
        completedExpected += item.sizeBytes;
      }

      MediaRepository.instance.invalidate();
      await ref.read(mediaLibraryProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _receivedCount = received.length;
        _lastReceivedPath = received.isNotEmpty ? received.last : null;
        _progress = 1;
      });
    } on TransferCancelledException {
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'The transfer did not finish. Keep both phones connected and try again.');
    } finally {
      if (mounted) {
        setState(() {
          _receiving = false;
          _scanLocked = false;
          _cancelRequested = false;
        });
      }
    }
  }

  void _cancelReceive() {
    _cancelRequested = true;
    _receiver.cancel();
    if (mounted) {
      setState(() {
        _receiving = false;
        _progress = 0;
        _scanLocked = false;
      });
    }
  }

  _TransferMediaKind _mediaKindForName(String name) {
    final lower = name.toLowerCase();
    const videos = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.ts'};
    return videos.any(lower.endsWith)
        ? _TransferMediaKind.videos
        : _TransferMediaKind.music;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
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
              onPressed: () async {
                await _sender.stop();
                if (!mounted) return;
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
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _mode == _TransferMode.send
                    ? _sendBody(context, library)
                    : _receiveBody(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _ModeSwitch(mode: _mode, onChanged: _switchMode),
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

    if (_shareUrl != null && _selectedMedia.isNotEmpty) {
      final selected = _selectedMedia.values.toList(growable: false);
      final videos = selected.where((item) => item.isVideo).length;
      final music = selected.length - videos;
      final totalBytes = selected.fold<int>(
        0,
        (sum, item) => sum + item.fileSizeBytes,
      );
      return ListView(
        key: const ValueKey('send-ready'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          if (_hotspotInfo != null) ...[
            _HotspotDetails(info: _hotspotInfo!),
            const SizedBox(height: 18),
          ],
          Text(
            '${selected.length} ${selected.length == 1 ? 'item' : 'items'} ready',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -.6,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${videos > 0 ? '$videos video${videos == 1 ? '' : 's'}' : ''}'
            '${videos > 0 && music > 0 ? ' · ' : ''}'
            '${music > 0 ? '$music song${music == 1 ? '' : 's'}' : ''}'
            ' · ${_formatBytes(totalBytes)}',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Open Receive on the other phone and scan once. Otya will receive the whole selection in order.',
            style: TextStyle(
              fontSize: 12.5,
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
          ...selected.take(4).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Icon(
                        item.isVideo
                            ? Icons.video_library_rounded
                            : Icons.music_note_rounded,
                        size: 18,
                        color: AppColors.brandCyan,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (selected.length > 4)
            Text(
              '+ ${selected.length - 4} more',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
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
            onPressed: () async {
              await _sender.stop();
              if (!mounted) return;
              setState(() => _shareUrl = null);
            },
            child: const Text('Change selection'),
          ),
        ],
      );
    }

    final filtered = library
        .where((item) =>
            _mediaKind == _TransferMediaKind.videos ? item.isVideo : !item.isVideo)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final allVisibleSelected = filtered.isNotEmpty &&
        filtered.every((item) => _selectedMedia.containsKey(item.id));
    final selectedBytes = _selectedMedia.values.fold<int>(
      0,
      (sum, item) => sum + item.fileSizeBytes,
    );

    return Column(
      key: const ValueKey('send-picker'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
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
                'Tap as many items as you want. Your selection stays when you switch between Videos and Music.',
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedMedia.isEmpty
                          ? 'Nothing selected yet'
                          : '${_selectedMedia.length} selected · ${_formatBytes(selectedBytes)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (filtered.isNotEmpty)
                    TextButton(
                      onPressed: _sending ? null : () => _toggleAllVisible(filtered),
                      child: Text(
                        allVisibleSelected
                            ? 'Clear ${_mediaKind == _TransferMediaKind.videos ? 'videos' : 'music'}'
                            : 'Select all',
                      ),
                    ),
                ],
              ),
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
                    selected: _selectedMedia.containsKey(item.id),
                    onTap: _sending ? null : () => _toggleSelection(item),
                  ),
                ),
            ],
          ),
        ),
        if (_selectedMedia.isNotEmpty)
          _SelectionBar(
            count: _selectedMedia.length,
            sizeLabel: _formatBytes(selectedBytes),
            busy: _sending,
            onSend: _sendSelected,
            onClear: _sending
                ? null
                : () => setState(() => _selectedMedia.clear()),
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

    if (_receivedCount > 0) {
      final name = _lastReceivedPath?.replaceAll('\\', '/').split('/').last;
      final singleKind = name == null ? null : _mediaKindForName(name);
      return _ResultView(
        key: const ValueKey('receive-done'),
        icon: Icons.check_circle_rounded,
        title: _receivedCount == 1
            ? singleKind == _TransferMediaKind.videos
                ? 'Video received'
                : 'Music received'
            : '$_receivedCount items received',
        subtitle: _receivedCount == 1 && name != null
            ? '$name\nSaved in Otya → Received → '
                '${singleKind == _TransferMediaKind.videos ? 'Videos' : 'Music'}.'
            : 'Saved in Otya → Received, with videos and music kept in their own folders.',
        action: 'Receive more',
        onAction: () => setState(() {
          _lastReceivedPath = null;
          _receivedCount = 0;
          _error = null;
          _progress = 0;
          _scanLocked = false;
          _receiveItemIndex = 0;
          _receiveItemCount = 0;
        }),
      );
    }

    if (_receiving) {
      return ListView(
        key: const ValueKey('receiving'),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 54),
          const Icon(
            Icons.downloading_rounded,
            size: 62,
            color: AppColors.brandCyan,
          ),
          const SizedBox(height: 20),
          Text(
            _receiveItemCount > 1
                ? 'Receiving $_receiveItemIndex of $_receiveItemCount'
                : 'Receiving',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
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
            onPressed: _cancelReceive,
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
                    'One scan can receive one item or a whole selected batch.',
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

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.sizeLabel,
    required this.busy,
    required this.onSend,
    required this.onClear,
  });

  final int count;
  final String sizeLabel;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.brandCyan.withValues(alpha: .22),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: .12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count selected',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sizeLabel,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Clear selection',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 3),
            FilledButton.icon(
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(busy ? 'Preparing' : 'Send $count'),
            ),
          ],
        ),
      );
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
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
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
              child: Icon(primaryIcon, size: 34, color: Colors.white),
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
  const _MediaRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MediaItem item;
  final bool selected;
  final VoidCallback? onTap;

  String _folder(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.length > 1 ? parts[parts.length - 2] : 'Device';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected
              ? AppColors.brandBlue.withValues(alpha: .12)
              : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? AppColors.brandCyan.withValues(alpha: .34)
                      : AppColors.borderOf(context).withValues(alpha: .55),
                ),
              ),
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: selected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            key: ValueKey('selected'),
                            color: AppColors.brandCyan,
                          )
                        : const Icon(
                            Icons.radio_button_unchecked_rounded,
                            key: ValueKey('not-selected'),
                            color: AppColors.textSecondary,
                          ),
                  ),
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
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
                textAlign: TextAlign.center,
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
