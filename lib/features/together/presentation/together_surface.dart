import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../domain/together_message.dart';
import '../domain/together_session.dart';

/// The only persistent Together control intended for the video player.
///
/// It appears only while a Together session exists and disappears with the
/// normal playback controls. Chat/people/settings never become separate player
/// buttons, keeping the player visually one OTYA experience.
class TogetherStatusButton extends StatelessWidget {
  final TogetherSessionPhase phase;
  final int participantCount;
  final int unreadMessages;
  final VoidCallback onPressed;

  const TogetherStatusButton({
    super.key,
    required this.phase,
    required this.participantCount,
    required this.unreadMessages,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final active = phase == TogetherSessionPhase.watching ||
        phase == TogetherSessionPhase.afterWatch;
    final reconnecting = phase == TogetherSessionPhase.reconnecting ||
        phase == TogetherSessionPhase.connecting;

    return Semantics(
      button: true,
      label: unreadMessages > 0
          ? 'Together, $participantCount people, $unreadMessages unread messages'
          : 'Together, $participantCount people',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reconnecting
                      ? Colors.amberAccent
                      : active
                          ? AppColors.accent
                          : Colors.white54,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'Together',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              if (participantCount > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$participantCount',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              if (unreadMessages > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadMessages > 99 ? '99+' : '$unreadMessages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showTogetherRoomSurface({
  required BuildContext context,
  required TogetherSession session,
  required List<TogetherMessage> messages,
  required String localParticipantId,
  required ValueChanged<String> onSendMessage,
  required ValueChanged<Duration> onMomentTap,
  required VoidCallback onInvite,
  required VoidCallback onLeave,
  VoidCallback? onReplay,
  VoidCallback? onChooseNext,
}) async {
  final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

  Widget content(BuildContext surfaceContext) => TogetherRoomContent(
        session: session,
        messages: messages,
        localParticipantId: localParticipantId,
        onSendMessage: onSendMessage,
        onMomentTap: onMomentTap,
        onInvite: onInvite,
        onLeave: onLeave,
        onReplay: onReplay,
        onChooseNext: onChooseNext,
        onClose: () => Navigator.of(surfaceContext).pop(),
      );

  if (!landscape) {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: .98),
      barrierColor: Colors.black.withValues(alpha: .30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .64,
        child: content(sheetContext),
      ),
    );
    return;
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Together',
    barrierColor: Colors.black.withValues(alpha: .18),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) => SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Theme.of(dialogContext).colorScheme.surface.withValues(alpha: .96),
          elevation: 18,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: MediaQuery.sizeOf(dialogContext).width.clamp(320, 430).toDouble(),
            height: double.infinity,
            child: content(dialogContext),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class TogetherRoomContent extends StatefulWidget {
  final TogetherSession session;
  final List<TogetherMessage> messages;
  final String localParticipantId;
  final ValueChanged<String> onSendMessage;
  final ValueChanged<Duration> onMomentTap;
  final VoidCallback onInvite;
  final VoidCallback onLeave;
  final VoidCallback onClose;
  final VoidCallback? onReplay;
  final VoidCallback? onChooseNext;

  const TogetherRoomContent({
    super.key,
    required this.session,
    required this.messages,
    required this.localParticipantId,
    required this.onSendMessage,
    required this.onMomentTap,
    required this.onInvite,
    required this.onLeave,
    required this.onClose,
    this.onReplay,
    this.onChooseNext,
  });

  @override
  State<TogetherRoomContent> createState() => _TogetherRoomContentState();
}

class _TogetherRoomContentState extends State<TogetherRoomContent> {
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      children: [
        _RoomHeader(
          session: session,
          onClose: widget.onClose,
        ),
        if (session.isAfterWatch)
          _AfterWatchBar(
            onReplay: widget.onReplay,
            onChooseNext: widget.onChooseNext,
          ),
        _ParticipantStrip(participants: session.participants),
        const Divider(height: 1),
        Expanded(
          child: widget.messages.isEmpty
              ? const _EmptyConversation()
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, reverseIndex) {
                    final index = widget.messages.length - 1 - reverseIndex;
                    final message = widget.messages[index];
                    final participant = session.participants
                        .where((item) => item.id == message.senderParticipantId)
                        .firstOrNull;
                    return _MessageBubble(
                      message: message,
                      senderName: participant?.displayName ?? 'OTYA',
                      own: message.senderParticipantId == widget.localParticipantId,
                      onMomentTap: widget.onMomentTap,
                    );
                  },
                ),
        ),
        _ConversationComposer(
          controller: _messageController,
          onSend: _send,
          onInvite: widget.onInvite,
          onLeave: widget.onLeave,
        ),
      ],
    );
  }
}

class _RoomHeader extends StatelessWidget {
  final TogetherSession session;
  final VoidCallback onClose;

  const _RoomHeader({required this.session, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final status = switch (session.phase) {
      TogetherSessionPhase.connecting => 'Connecting',
      TogetherSessionPhase.reconnecting => 'Reconnecting',
      TogetherSessionPhase.afterWatch => 'After watching',
      TogetherSessionPhase.watching => 'Watching together',
      TogetherSessionPhase.creating => 'Starting',
      TogetherSessionPhase.closed => 'Ended',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_alt_rounded, color: AppColors.accent, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Together', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _AfterWatchBar extends StatelessWidget {
  final VoidCallback? onReplay;
  final VoidCallback? onChooseNext;

  const _AfterWatchBar({this.onReplay, this.onChooseNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: .16)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Finished',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (onReplay != null)
            TextButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Replay'),
            ),
          if (onChooseNext != null)
            FilledButton.tonalIcon(
              onPressed: onChooseNext,
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: const Text('Next'),
            ),
        ],
      ),
    );
  }
}

class _ParticipantStrip extends StatelessWidget {
  final List<TogetherParticipant> participants;

  const _ParticipantStrip({required this.participants});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        itemCount: participants.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final participant = participants[index];
          final initial = participant.displayName.trim().isEmpty
              ? '?'
              : participant.displayName.trim()[0].toUpperCase();
          return Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.accent.withValues(alpha: .14),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant.displayName,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                    if (participant.username != null)
                      Text(
                        participant.username!.startsWith('@')
                            ? participant.username!
                            : '@${participant.username!}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 9.5,
                            ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: participant.isConnected ? AppColors.accent : Colors.white38,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 30,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            const Text('Watch first. Talk when you want.', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(
              'Messages stay inside this Together session.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TogetherMessage message;
  final String senderName;
  final bool own;
  final ValueChanged<Duration> onMomentTap;

  const _MessageBubble({
    required this.message,
    required this.senderName,
    required this.own,
    required this.onMomentTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.kind == TogetherMessageKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: own
              ? AppColors.accent.withValues(alpha: .15)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!own)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  senderName,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            Text(message.text, style: const TextStyle(height: 1.35)),
            if (message.isMoment && message.mediaPosition != null) ...[
              const SizedBox(height: 5),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onMomentTap(message.mediaPosition!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 1),
                  child: Text(
                    'Moment · ${_formatDuration(message.mediaPosition!)}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _ConversationComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onInvite;
  final VoidCallback onLeave;

  const _ConversationComposer({
    required this.controller,
    required this.onSend,
    required this.onInvite,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          children: [
            PopupMenuButton<String>(
              tooltip: 'Together options',
              onSelected: (value) {
                if (value == 'invite') onInvite();
                if (value == 'leave') onLeave();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'invite', child: Text('Invite')),
                PopupMenuItem(value: 'leave', child: Text('Leave Together')),
              ],
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                maxLength: TogetherMessage.maxTextLength,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Message…',
                  counterText: '',
                  isDense: true,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Send message',
              onPressed: onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
