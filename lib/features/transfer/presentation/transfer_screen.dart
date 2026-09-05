import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:otya_transfer_android/otya_transfer_android.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../my_space/data/media_repository.dart';
import '../../my_space/presentation/providers/my_space_provider.dart';
import '../data/media_receiver.dart';
import '../data/media_sender.dart';
import '../data/transfer_hotspot_service.dart';
import '../data/transfer_security_policy.dart';

enum _TransferMode { send, receive }
enum _TransferCategory { video, music, app }

class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final MediaSender _sender = MediaSender();
  final MediaReceiver _receiver = MediaReceiver();
  final MobileScannerController _scanner = MobileScannerController();

  _TransferMode _mode = _TransferMode.send;
  _TransferCategory _category = _TransferCategory.video;
  MediaItem? _selected;
  OtyaHotspotInfo? _hotspot;
  OtyaShareableApk? _shareableApk;
  String? _shareUrl;
  String? _browserUrl;
  String? _receivedPath;
  String? _error;
  double _progress = 0;
  bool _sending = false;
  bool _sharingApp = false;
  bool _receiving = false;
  bool _scanLocked = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShareableApk());
  }

  Future<void> _loadShareableApk() async {
    final apk = await TransferHotspotService.instance.shareableApk();
    if (!mounted) return;
    setState(() => _shareableApk = apk);
  }

  @override
  void dispose() {
    unawaited(_sender.stop());
    unawaited(TransferHotspotService.instance.stop());
    _receiver.cancel();
    unawaited(_scanner.stop());
    _scanner.dispose();
    super.dispose();
  }

  void _switchMode(_TransferMode mode) {
    HapticFeedback.selectionClick();
    if (_mode == mode) return;
    if (_mode == _TransferMode.send) unawaited(_endSendingSession());
    _receiver.cancel();
    setState(() {
      _mode = mode;
      _shareUrl = null;
      _browserUrl = null;
      _selected = null;
      _sharingApp = false;
      _receivedPath = null;
      _error = null;
      _progress = 0;
      _sending = false;
      _receiving = false;
      _scanLocked = false;
    });
  }

  Future<OtyaHotspotInfo?> _startOfflineHotspot() async {
    if (_hotspot != null) return _hotspot;
    if (_connecting) return null;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final hotspot = await TransferHotspotService.instance.start();
      if (!mounted) return hotspot;
      setState(() => _hotspot = hotspot);
      return hotspot;
    } on TransferHotspotException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return null;
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _endSendingSession() async {
    await _sender.stop();
    await TransferHotspotService.instance.stop();
    if (!mounted) return;
    setState(() {
      _hotspot = null;
      _shareUrl = null;
      _browserUrl = null;
      _selected = null;
      _sharingApp = false;
      _sending = false;
    });
  }

  Future<String> _serveMedia(MediaItem item) async {
    final appPath = _shareableApk?.available == true
        ? _shareableApk?.path
        : null;
    try {
      return await _sender.startServing(
        item.filePath,
        appApkPath: appPath,
      );
    } on StateError {
      final hotspot = await _startOfflineHotspot();
      if (hotspot == null) {
        throw StateError(
          'No local connection is available. Create the Otya offline hotspot or connect both phones to the same Wi-Fi.',
        );
      }
      return _sender.startServing(
        item.filePath,
        appApkPath: appPath,
      );
    }
  }

  Future<void> _send(MediaItem item) async {
    if (_sending) return;
    HapticFeedback.lightImpact();
    await _sender.stop();
    if (!mounted) return;
    setState(() {
      _selected = item;
      _sharingApp = false;
      _sending = true;
      _shareUrl = null;
      _browserUrl = null;
      _error = null;
    });
    try {
      final url = await _serveMedia(item);
      if (!mounted) return;
      setState(() {
        _shareUrl = url;
        _browserUrl = _sender.pageUrl;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is TransferHotspotException
            ? error.message
            : 'Otya could not create a reachable local transfer. Check Wi-Fi/hotspot and try again.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareOtyaApp() async {
    if (_sending) return;
    final apk = _shareableApk;
    if (apk == null) {
      await _loadShareableApk();
      return;
    }
    if (!apk.available || apk.path == null) {
      setState(() {
        _error = apk.reason ??
            'This Otya installation cannot be exported as one safe standalone APK.';
      });
      return;
    }

    HapticFeedback.lightImpact();
    await _sender.stop();
    if (!mounted) return;
    setState(() {
      _selected = null;
      _sharingApp = true;
      _sending = true;
      _shareUrl = null;
      _browserUrl = null;
      _error = null;
    });

    try {
      String page;
      try {
        page = await _sender.startServingApp(apk.path!);
      } on StateError {
        final hotspot = await _startOfflineHotspot();
        if (hotspot == null) {
          throw StateError('No local network is available for APK sharing.');
        }
        page = await _sender.startServingApp(apk.path!);
      }
      if (!mounted) return;
      setState(() => _browserUrl = page);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Otya could not prepare its APK for the nearby phone. Try the offline hotspot again.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _receive(String rawUrl) async {
    if (_receiving) return;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !isAllowedTransferUri(uri)) {
      setState(() {
        _error = 'OTYA Transfer only accepts an authenticated nearby Otya media link.';
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
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/OTYA_Received');
      await dir.create(recursive: true);
      final advertised = uri.queryParameters['name']
          ?.replaceAll('\\', '/')
          .split('/')
          .last
          .trim();
      final fileName = advertised != null && advertised.isNotEmpty
          ? advertised
          : 'received_${DateTime.now().millisecondsSinceEpoch}.bin';

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
      setState(() {
        _error = 'The transfer did not finish. Keep both phones on the same Otya hotspot/Wi-Fi and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _receiving = false;
          _scanLocked = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library =
        ref.watch(mediaLibraryProvider).valueOrNull ?? const <MediaItem>[];
    final hasSession = _browserUrl != null;

    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('OTYA Transfer'),
        actions: [
          if (hasSession)
            TextButton(
              onPressed: () => unawaited(_endSendingSession()),
              child: const Text('Stop'),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: _ModeSwitch(
                mode: _mode,
                onChanged: _switchMode,
              ),
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
    if (_browserUrl != null) return _readyToSend(context);

    final videos = library.where((item) => item.isVideo).toList(growable: false);
    final music = library.where((item) => !item.isVideo).toList(growable: false);
    final selectedItems = _category == _TransferCategory.video ? videos : music;

    return ListView(
      key: const ValueKey('send-picker'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Text(
          'Send nearby',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'No Internet is required. Use the same Wi-Fi, or let Otya create a local-only hotspot automatically.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        _ConnectionCard(
          hotspot: _hotspot,
          connecting: _connecting,
          onCreateHotspot: _startOfflineHotspot,
          onStopHotspot: _hotspot == null
              ? null
              : () async {
                  await _sender.stop();
                  await TransferHotspotService.instance.stop();
                  if (mounted) setState(() => _hotspot = null);
                },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error!),
        ],
        const SizedBox(height: 18),
        _CategoryTabs(
          category: _category,
          videoCount: videos.length,
          musicCount: music.length,
          appAvailable: _shareableApk?.available == true,
          onChanged: (category) {
            HapticFeedback.selectionClick();
            setState(() {
              _category = category;
              _error = null;
            });
          },
        ),
        const SizedBox(height: 16),
        if (_category == _TransferCategory.app)
          _OtyaAppCard(
            apk: _shareableApk,
            busy: _sending,
            onShare: _shareOtyaApp,
          )
        else if (selectedItems.isEmpty)
          _EmptyTransfer(
            icon: _category == _TransferCategory.video
                ? Icons.movie_outlined
                : Icons.music_note_rounded,
            title: _category == _TransferCategory.video
                ? 'No videos found'
                : 'No music found',
            subtitle: 'Add media to this device, then refresh your Otya library.',
          )
        else
          ...selectedItems.map(
            (item) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Icon(
                  item.isVideo
                      ? Icons.movie_outlined
                      : Icons.music_note_rounded,
                  size: 21,
                  color: item.isVideo
                      ? AppColors.brandCyan
                      : AppColors.brandBlue,
                ),
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                item.formattedSize,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: _sending && _selected?.id == item.id
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios_rounded, size: 15),
              onTap: _sending ? null : () => _send(item),
            ),
          ),
      ],
    );
  }

  Widget _readyToSend(BuildContext context) {
    final browserUrl = _browserUrl!;
    final selected = _selected;
    final title = _sharingApp ? 'Otya app' : selected?.title ?? 'Nearby share';
    final subtitle = _sharingApp
        ? _formatBytes(_shareableApk?.bytes ?? 0)
        : selected?.formattedSize ?? '';

    return ListView(
      key: const ValueKey('send-ready'),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
      children: [
        Text(
          'Ready to send',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _hotspot == null
              ? 'Keep both devices on this Wi-Fi until the transfer finishes.'
              : 'No Internet is being used. Connect the other phone to the Otya hotspot first.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        if (_hotspot != null) ...[
          const SizedBox(height: 18),
          _HotspotJoinCard(info: _hotspot!),
        ],
        if (_shareUrl != null) ...[
          const SizedBox(height: 18),
          _QrCard(
            title: 'Receive in Otya',
            subtitle: 'After joining the same Wi-Fi/hotspot, open Receive on the other Otya phone and scan this.',
            data: _shareUrl!,
          ),
        ],
        const SizedBox(height: 18),
        _QrCard(
          title: _sharingApp ? 'Install Otya on another phone' : 'Receive without Otya',
          subtitle: 'Scan this with the other phone camera or browser. It opens a local page directly from this phone.',
          data: browserUrl,
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: browserUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nearby browser link copied')),
            );
          },
          icon: const Icon(Icons.content_copy_rounded),
          label: const Text('Copy local browser link'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => unawaited(_endSendingSession()),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop sharing'),
        ),
      ],
    );
  }

  Widget _receiveBody(BuildContext context) {
    if (_receivedPath != null) {
      return _ResultView(
        key: const ValueKey('receive-done'),
        icon: Icons.check_circle_rounded,
        title: 'File received',
        subtitle:
            '${_receivedPath!.split('/').last}\nOTYA scanned it into your library when supported.',
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
          const SizedBox(height: 70),
          const Icon(
            Icons.downloading_rounded,
            size: 64,
            color: AppColors.brandCyan,
          ),
          const SizedBox(height: 22),
          const Text(
            'Receiving…',
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
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
      children: [
        Text(
          'Receive nearby',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'If the sender created an Otya hotspot, join it first using the Wi-Fi QR shown there. Then scan the Transfer QR below.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
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
                width: 280,
                height: 280,
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
        const SizedBox(height: 18),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_rounded,
              size: 17,
              color: AppColors.brandCyan,
            ),
            SizedBox(width: 7),
            Text(
              'Direct local transfer · no cloud relay',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.hotspot,
    required this.connecting,
    required this.onCreateHotspot,
    this.onStopHotspot,
  });

  final OtyaHotspotInfo? hotspot;
  final bool connecting;
  final Future<OtyaHotspotInfo?> Function() onCreateHotspot;
  final Future<void> Function()? onStopHotspot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.wifi_tethering_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hotspot == null ? 'Connection' : 'Offline hotspot ready',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hotspot == null
                        ? 'Same Wi-Fi works. Or create a private Otya hotspot with no Internet.'
                        : hotspot!.ssid,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (connecting)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (hotspot == null)
              TextButton(
                onPressed: () => unawaited(onCreateHotspot()),
                child: const Text('Create'),
              )
            else
              TextButton(
                onPressed: onStopHotspot == null
                    ? null
                    : () => unawaited(onStopHotspot!()),
                child: const Text('Stop'),
              ),
          ],
        ),
      );
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.category,
    required this.videoCount,
    required this.musicCount,
    required this.appAvailable,
    required this.onChanged,
  });

  final _TransferCategory category;
  final int videoCount;
  final int musicCount;
  final bool appAvailable;
  final ValueChanged<_TransferCategory> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _CategoryButton(
              label: 'Video',
              count: videoCount,
              icon: Icons.movie_outlined,
              active: category == _TransferCategory.video,
              onTap: () => onChanged(_TransferCategory.video),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CategoryButton(
              label: 'Music',
              count: musicCount,
              icon: Icons.music_note_rounded,
              active: category == _TransferCategory.music,
              onTap: () => onChanged(_TransferCategory.music),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CategoryButton(
              label: 'Otya',
              count: appAvailable ? 1 : 0,
              icon: Icons.android_rounded,
              active: category == _TransferCategory.app,
              onTap: () => onChanged(_TransferCategory.app),
            ),
          ),
        ],
      );
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? AppColors.accentGradient : null,
            color: active ? null : AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: active ? Colors.transparent : AppColors.borderOf(context),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: active ? Colors.white : AppColors.brandCyan),
              const SizedBox(height: 4),
              Text(
                '$label · $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      );
}

class _OtyaAppCard extends StatelessWidget {
  const _OtyaAppCard({
    required this.apk,
    required this.busy,
    required this.onShare,
  });

  final OtyaShareableApk? apk;
  final bool busy;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    final available = apk?.available == true && apk?.path != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.android_rounded, color: AppColors.brandCyan, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Share Otya itself', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Text('Send the installed standalone APK over Wi-Fi/hotspot with no Internet.', style: TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (apk == null)
            const LinearProgressIndicator(minHeight: 3)
          else if (!available)
            Text(
              apk!.reason ?? 'This installation cannot be shared as one APK.',
              style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
            )
          else
            Text(
              _formatBytes(apk!.bytes),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !available || busy ? null : () => unawaited(onShare()),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Share Otya offline'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotspotJoinCard extends StatelessWidget {
  const _HotspotJoinCard({required this.info});

  final OtyaHotspotInfo info;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          children: [
            const Text(
              '1 · Join this Wi-Fi first',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Scan with the other phone camera/Wi-Fi settings. The hotspot has no Internet by design.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: info.wifiQrPayload,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              info.ssid,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (info.passphrase?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              SelectableText(
                info.passphrase!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      );
}

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.title,
    required this.subtitle,
    required this.data,
  });

  final String title;
  final String subtitle;
  final String data;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: .14),
                    blurRadius: 26,
                  ),
                ],
              ),
              child: QrImageView(
                data: data,
                size: 210,
                backgroundColor: Colors.white,
              ),
            ),
          ],
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
              color: active ? null : Colors.transparent,
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
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
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
        padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
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

String _formatBytes(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
