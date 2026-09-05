import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../application/nearby_together_runtime.dart';
import '../application/nearby_together_session.dart';
import '../application/together_guest_media_session.dart';
import '../data/together_stream_cache_proxy.dart';

Future<NearbyPlaybackPlan?> showNearbyTogetherJoinSheet({
  required BuildContext context,
  required MediaItem currentMediaItem,
  required Player player,
  String? displayName,
}) {
  return showModalBottomSheet<NearbyPlaybackPlan>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black.withValues(alpha: .42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _NearbyTogetherJoinSheet(
      currentMediaItem: currentMediaItem,
      player: player,
      displayName: displayName,
    ),
  );
}

class _NearbyTogetherJoinSheet extends StatefulWidget {
  final MediaItem currentMediaItem;
  final Player player;
  final String? displayName;

  const _NearbyTogetherJoinSheet({
    required this.currentMediaItem,
    required this.player,
    required this.displayName,
  });

  @override
  State<_NearbyTogetherJoinSheet> createState() => _NearbyTogetherJoinSheetState();
}

class _NearbyTogetherJoinSheetState extends State<_NearbyTogetherJoinSheet> {
  final MobileScannerController _scanner = MobileScannerController();
  final TextEditingController _inviteController = TextEditingController();

  bool _joining = false;
  bool _scanLocked = false;
  bool _keepVideo = false;
  String? _error;

  @override
  void dispose() {
    _scanner.stop();
    _scanner.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _join(String rawInvite) async {
    if (_joining) return;
    final uri = Uri.tryParse(rawInvite.trim());
    if (uri == null || uri.scheme != 'ws') {
      setState(() {
        _error = 'That is not a valid Otya Together invite.';
        _scanLocked = false;
      });
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _joining = true;
      _error = null;
    });
    await _scanner.stop();

    try {
      final joinedPlan = await NearbyTogetherRuntime.instance.joinGuest(
        inviteUri: uri,
        candidateMediaItem: widget.currentMediaItem,
        player: widget.player,
        displayName: widget.displayName,
      );
      final playbackPlan = await TogetherGuestMediaSession.instance.prepare(
        plan: joinedPlan,
        mode: _keepVideo
            ? TogetherStreamMode.streamAndSave
            : TogetherStreamMode.streamOnly,
      );
      if (!mounted) return;
      Navigator.of(context).pop(playbackPlan);
    } catch (_) {
      await NearbyTogetherRuntime.instance.stop();
      if (!mounted) return;
      setState(() {
        _error = NearbyTogetherRuntime.instance.lastError ??
            TogetherGuestMediaSession.instance.lastError ??
            'Otya could not join this Together session.';
        _joining = false;
        _scanLocked = false;
      });
      await _scanner.start();
    }
  }

  Future<void> _pasteInvite() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      setState(() => _error = 'There is no Together invite on your clipboard.');
      return;
    }
    _inviteController.text = text;
    await _join(text);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Join Together',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Scan the private invite from your friend’s Otya.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _joining ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.error.withValues(alpha: .20)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                    const SizedBox(width: 9),
                    Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppColors.accent.withValues(alpha: .35), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: .12),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: MobileScanner(
                          controller: _scanner,
                          fit: BoxFit.cover,
                          onDetect: (capture) {
                            if (_scanLocked || _joining || capture.barcodes.isEmpty) return;
                            final value = capture.barcodes.first.rawValue ??
                                capture.barcodes.first.displayValue;
                            if (value == null || !value.startsWith('ws://')) return;
                            _scanLocked = true;
                            _join(value);
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_joining)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .45),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(strokeWidth: 2.4),
                              SizedBox(height: 12),
                              Text(
                                'Connecting…',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _inviteController,
              enabled: !_joining,
              maxLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Together invite',
                hintText: 'Paste the invite here',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Paste invite',
                  onPressed: _joining ? null : _pasteInvite,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
              onSubmitted: _joining ? null : _join,
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SwitchListTile.adaptive(
                value: _keepVideo,
                onChanged: _joining
                    ? null
                    : (value) => setState(() => _keepVideo = value),
                secondary: Icon(
                  _keepVideo ? Icons.download_done_rounded : Icons.memory_rounded,
                  color: _keepVideo ? AppColors.accent : AppColors.textSecondary,
                ),
                title: const Text(
                  'Keep video',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _keepVideo
                      ? 'Otya reuses what you already watched, finishes only missing parts, and keeps progress if the connection stops.'
                      : 'Watch without keeping the movie. Temporary playback data is removed when the session ends.',
                  style: const TextStyle(fontSize: 11.5, height: 1.35),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _joining
                  ? null
                  : () => _join(_inviteController.text),
              icon: const Icon(Icons.people_alt_rounded),
              label: const Text('Join'),
            ),
            const SizedBox(height: 7),
            const Text(
              'Nearby Together works on the same Wi-Fi or hotspot. The video stays between your phones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
