import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../application/anywhere_together_runtime.dart';
import '../data/together_control_client.dart';

class AnywhereTogetherJoinCode {
  final String roomId;
  final String inviteToken;

  const AnywhereTogetherJoinCode({
    required this.roomId,
    required this.inviteToken,
  });
}

String encodeAnywhereTogetherInvite(AnywhereTogetherInvite invite) {
  return Uri(
    scheme: 'otya',
    host: 'together',
    path: '/anywhere',
    queryParameters: {
      'room': invite.roomId,
      'token': invite.inviteToken,
    },
  ).toString();
}

AnywhereTogetherJoinCode? parseAnywhereTogetherInvite(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.length > 1024) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'otya' ||
      uri.host.toLowerCase() != 'together' ||
      uri.path != '/anywhere' ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  final room = uri.queryParameters['room']?.trim() ?? '';
  final token = uri.queryParameters['token']?.trim() ?? '';
  if (room.isEmpty ||
      room.length > 160 ||
      token.isEmpty ||
      token.length > 512) {
    return null;
  }
  return AnywhereTogetherJoinCode(roomId: room, inviteToken: token);
}

Future<void> showAnywhereTogetherHostSheet({
  required BuildContext context,
  required MediaItem mediaItem,
  required Player player,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface.withValues(alpha: .99),
    barrierColor: Colors.black.withValues(alpha: .42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _AnywhereHostSheet(
      mediaItem: mediaItem,
      player: player,
    ),
  );
}

Future<AnywherePlaybackPlan?> showAnywhereTogetherJoinSheet({
  required BuildContext context,
  required MediaItem currentMediaItem,
  required Player player,
}) {
  return showModalBottomSheet<AnywherePlaybackPlan>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface.withValues(alpha: .99),
    barrierColor: Colors.black.withValues(alpha: .42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _AnywhereJoinSheet(
      currentMediaItem: currentMediaItem,
      player: player,
    ),
  );
}

class _AnywhereHostSheet extends StatefulWidget {
  final MediaItem mediaItem;
  final Player player;

  const _AnywhereHostSheet({
    required this.mediaItem,
    required this.player,
  });

  @override
  State<_AnywhereHostSheet> createState() => _AnywhereHostSheetState();
}

class _AnywhereHostSheetState extends State<_AnywhereHostSheet> {
  final _usernameController = TextEditingController();
  bool _working = false;
  String? _error;

  AnywhereTogetherRuntime get _runtime => AnywhereTogetherRuntime.instance;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty || username.length > 80) {
      setState(() => _error = 'Enter the OTYA username of the person you want to invite.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _runtime.startHost(
        mediaItem: widget.mediaItem,
        player: widget.player,
        inviteUsername: username,
      );
      if (mounted) setState(() => _working = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _runtime.lastError ?? 'OTYA could not start Anywhere Together.';
      });
    }
  }

  Future<void> _copyInvite(AnywhereTogetherInvite invite) async {
    await Clipboard.setData(
      ClipboardData(text: encodeAnywhereTogetherInvite(invite)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Private Together invite copied.'),
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invite = _runtime.isHost ? _runtime.invite : null;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 22 + bottom),
      child: invite == null ? _buildCreate() : _buildInvite(invite),
    );
  }

  Widget _buildCreate() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        const _SheetHeading(
          icon: Icons.public_rounded,
          title: 'Start Anywhere',
          subtitle: 'Invite one signed-in OTYA friend. The connection stays private between your phones.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _usernameController,
          enabled: !_working,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _working ? null : _start(),
          decoration: const InputDecoration(
            labelText: 'Friend username',
            hintText: '@username',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.error, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _working ? null : _start,
          icon: _working
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_outline_rounded),
          label: Text(_working ? 'Creating private room…' : 'Create private room'),
        ),
      ],
    );
  }

  Widget _buildInvite(AnywhereTogetherInvite invite) {
    final code = encodeAnywhereTogetherInvite(invite);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        _SheetHeading(
          icon: Icons.lock_rounded,
          title: 'Room ready',
          subtitle: 'OTYA invited @${invite.guestUsername} inside the app. They can open Together and tap Join. Keep OTYA open while they connect.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: SelectableText(
            code,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _copyInvite(invite),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy fallback invite'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to video'),
        ),
      ],
    );
  }
}

class _AnywhereJoinSheet extends StatefulWidget {
  final MediaItem currentMediaItem;
  final Player player;

  const _AnywhereJoinSheet({
    required this.currentMediaItem,
    required this.player,
  });

  @override
  State<_AnywhereJoinSheet> createState() => _AnywhereJoinSheetState();
}

class _AnywhereJoinSheetState extends State<_AnywhereJoinSheet> {
  final _inviteController = TextEditingController();
  bool _working = false;
  bool _loadingInvites = true;
  List<TogetherRemoteRoom> _invites = const [];
  String? _error;

  AnywhereTogetherRuntime get _runtime => AnywhereTogetherRuntime.instance;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _loadInvites() async {
    if (mounted && !_loadingInvites) {
      setState(() => _loadingInvites = true);
    }
    final result = await TogetherControlClient.instance.pendingInvites();
    if (!mounted) return;
    setState(() {
      _loadingInvites = false;
      _invites = result.value ?? const [];
      if (!result.ok) {
        _error = result.error;
      } else if (_error == result.error) {
        _error = null;
      }
    });
  }

  Future<void> _joinPending(TogetherRemoteRoom room) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final plan = await _runtime.joinGuest(
        roomId: room.roomId,
        player: widget.player,
        candidateMediaItem: widget.currentMediaItem,
      );
      if (!mounted) return;
      Navigator.of(context).pop(plan);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _runtime.lastError ?? 'OTYA could not join this private room.';
      });
    }
  }

  Future<void> _joinFromLink() async {
    final code = parseAnywhereTogetherInvite(_inviteController.text);
    if (code == null) {
      setState(() => _error = 'Paste a valid older Anywhere Together invite.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final plan = await _runtime.joinGuest(
        roomId: code.roomId,
        inviteToken: code.inviteToken,
        player: widget.player,
        candidateMediaItem: widget.currentMediaItem,
      );
      if (!mounted) return;
      Navigator.of(context).pop(plan);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _runtime.lastError ?? 'OTYA could not join this private room.';
      });
    }
  }

  Widget _pendingInvitesSection() {
    if (_loadingInvites) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_invites.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'No pending invitations. A friend only needs your @username to invite you.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            IconButton(
              onPressed: _working ? null : _loadInvites,
              tooltip: 'Refresh invitations',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final room in _invites)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.surfaceHighlight,
                  child: Icon(
                    Icons.person_rounded,
                    color: AppColors.brandCyan,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.host.displayName?.trim().isNotEmpty == true
                            ? room.host.displayName!
                            : room.host.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${room.host.handle} invited you to watch Together',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _working ? null : () => _joinPending(room),
                  child: const Text('Join'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 22 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 18),
            const _SheetHeading(
              icon: Icons.groups_rounded,
              title: 'Join Anywhere',
              subtitle: 'Invitations sent to your OTYA username appear here. Matching local media is reused first to save mobile data.',
            ),
            const SizedBox(height: 18),
            _pendingInvitesSection(),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Older invite link',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inviteController,
              enabled: !_working,
              autocorrect: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _working ? null : _joinFromLink(),
              decoration: const InputDecoration(
                labelText: 'Fallback private invite',
                hintText: 'otya://together/anywhere?…',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _working ? null : _joinFromLink,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Join from link'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _SheetHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SheetHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: AppColors.accent.withValues(alpha: .12),
          child: Icon(icon, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
