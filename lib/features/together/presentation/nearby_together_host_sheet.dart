import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../application/nearby_together_runtime.dart';

Future<void> showNearbyTogetherHostSheet({
  required BuildContext context,
  required MediaItem mediaItem,
  required Player player,
  String? displayName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black.withValues(alpha: .36),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _NearbyTogetherHostSheet(
      mediaItem: mediaItem,
      player: player,
      displayName: displayName,
    ),
  );
}

class _NearbyTogetherHostSheet extends StatefulWidget {
  final MediaItem mediaItem;
  final Player player;
  final String? displayName;

  const _NearbyTogetherHostSheet({
    required this.mediaItem,
    required this.player,
    required this.displayName,
  });

  @override
  State<_NearbyTogetherHostSheet> createState() => _NearbyTogetherHostSheetState();
}

class _NearbyTogetherHostSheetState extends State<_NearbyTogetherHostSheet> {
  final NearbyTogetherRuntime _runtime = NearbyTogetherRuntime.instance;
  bool _working = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _runtime.addListener(_runtimeChanged);
  }

  @override
  void dispose() {
    _runtime.removeListener(_runtimeChanged);
    super.dispose();
  }

  void _runtimeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_working || _runtime.starting) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _working = true;
      _localError = null;
    });
    try {
      await _runtime.startHost(
        mediaItem: widget.mediaItem,
        player: widget.player,
        displayName: widget.displayName,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _localError = _runtime.lastError);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stop() async {
    HapticFeedback.selectionClick();
    setState(() => _working = true);
    await _runtime.stop();
    if (mounted) {
      setState(() {
        _working = false;
        _localError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _runtime.invite;
    final session = _runtime.state.session;
    final error = _localError ?? _runtime.lastError;

    return FractionallySizedBox(
      heightFactor: invite == null ? .58 : .86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
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
                  child: const Icon(
                    Icons.people_alt_rounded,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Watch Together',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'One video. Two phones. Same moment.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.mediaItem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.mediaItem.formattedDuration} · ${widget.mediaItem.formattedSize}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.error.withValues(alpha: .22)),
                ),
                child: Text(error, style: const TextStyle(fontSize: 12.5)),
              ),
            ],
            const SizedBox(height: 16),
            if (invite == null) ...[
              const _HowItWorks(),
              const Spacer(),
              FilledButton.icon(
                onPressed: _working || _runtime.starting ? null : _start,
                icon: _working || _runtime.starting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline_rounded),
                label: Text(_working || _runtime.starting ? 'Starting…' : 'Start Together'),
              ),
              const SizedBox(height: 8),
              Text(
                'No account or internet is required when both phones are nearby.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ] else ...[
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 2),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: QrImageView(
                          data: invite.uri.toString(),
                          size: 220,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Scan this from OTYA on the other phone',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Keep both phones on the same Wi-Fi or hotspot. The movie stays between the phones.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: invite.uri.toString()),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Together invite copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy invite'),
                        ),
                        if (session != null)
                          Chip(
                            avatar: Icon(
                              session.connectedParticipantCount > 1
                                  ? Icons.check_circle_rounded
                                  : Icons.wifi_tethering_rounded,
                              size: 17,
                              color: session.connectedParticipantCount > 1
                                  ? AppColors.accent
                                  : null,
                            ),
                            label: Text(
                              session.connectedParticipantCount > 1
                                  ? 'Connected'
                                  : 'Waiting for friend',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You can close this sheet after sharing the invite. Together keeps running with the current player.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End Together'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _Step(
          icon: Icons.wifi_rounded,
          title: 'Be nearby',
          text: 'Use the same Wi-Fi or one phone’s hotspot.',
        ),
        SizedBox(height: 10),
        _Step(
          icon: Icons.qr_code_2_rounded,
          title: 'Scan once',
          text: 'Your friend scans the private Together invite.',
        ),
        SizedBox(height: 10),
        _Step(
          icon: Icons.sync_rounded,
          title: 'Watch as one',
          text: 'Playback and conversation stay connected without uploading the movie.',
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Step({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: .10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.accent, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
