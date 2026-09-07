import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../application/nearby_together_runtime.dart';
import '../domain/together_message.dart';
import '../domain/together_session.dart';

/// Ambient Together activity that belongs to the video, not to a chat screen.
///
/// Recent text/Moment messages briefly sit above the lower-left playback-safe
/// region. Reactions float separately on the right. The layer stays compact,
/// fades by itself, and expands into the full conversation only when tapped.
class TogetherAmbientOverlay extends StatefulWidget {
  const TogetherAmbientOverlay({
    super.key,
    required this.controlsVisible,
    required this.onOpenConversation,
  });

  final bool controlsVisible;
  final VoidCallback onOpenConversation;

  @override
  State<TogetherAmbientOverlay> createState() =>
      _TogetherAmbientOverlayState();
}

class _TogetherAmbientOverlayState extends State<TogetherAmbientOverlay> {
  Timer? _expiryTicker;

  @override
  void initState() {
    super.initState();
    _expiryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && NearbyTogetherRuntime.instance.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = NearbyTogetherRuntime.instance;
    return AnimatedBuilder(
      animation: runtime,
      builder: (context, _) {
        final session = runtime.state.session;
        if (session == null || !session.isActive) {
          return const SizedBox.shrink();
        }

        final now = DateTime.now().toUtc();
        final recentMessages = runtime.state.messages
            .where((message) =>
                message.kind != TogetherMessageKind.system &&
                message.kind != TogetherMessageKind.reaction &&
                now.difference(message.createdAt).abs() <=
                    const Duration(seconds: 8))
            .toList(growable: false);
        final visibleMessages = recentMessages.length <= 3
            ? recentMessages
            : recentMessages.sublist(recentMessages.length - 3);

        final recentReactions = runtime.state.messages
            .where((message) =>
                message.isReaction &&
                now.difference(message.createdAt).abs() <=
                    const Duration(seconds: 4))
            .toList(growable: false);
        final visibleReactions = recentReactions.length <= 3
            ? recentReactions
            : recentReactions.sublist(recentReactions.length - 3);

        if (visibleMessages.isEmpty && visibleReactions.isEmpty) {
          return const SizedBox.shrink();
        }

        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final bottom = widget.controlsVisible
            ? (landscape ? 118.0 : 154.0)
            : (landscape ? 30.0 : 42.0);
        final maxWidth = landscape
            ? MediaQuery.sizeOf(context).width * .42
            : MediaQuery.sizeOf(context).width * .78;

        return Stack(
          children: [
            if (visibleMessages.isNotEmpty)
              Positioned(
                left: 14,
                bottom: bottom,
                child: Semantics(
                  button: true,
                  label: 'Open Together conversation',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenConversation,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth.clamp(240.0, 520.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final message in visibleMessages)
                            _AmbientMessageRow(
                              key: ValueKey(message.id),
                              message: message,
                              sender: _senderName(session, message),
                              own: message.senderParticipantId ==
                                  runtime.localParticipantId,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (visibleReactions.isNotEmpty)
              Positioned(
                right: 18,
                bottom: bottom + 10,
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0;
                          index < visibleReactions.length;
                          index++)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _AmbientReaction(
                            key: ValueKey(visibleReactions[index].id),
                            reaction: visibleReactions[index].text,
                            index: index,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _senderName(TogetherSession session, TogetherMessage message) {
    final id = message.senderParticipantId;
    if (id == NearbyTogetherRuntime.instance.localParticipantId) return 'You';
    final participant = session.participants
        .where((item) => item.id == id)
        .firstOrNull;
    if (participant == null) return 'Together';
    final username = participant.username?.trim();
    if (username?.isNotEmpty == true) {
      return username!.startsWith('@') ? username : '@$username';
    }
    return participant.displayName;
  }
}

class _AmbientMessageRow extends StatelessWidget {
  const _AmbientMessageRow({
    super.key,
    required this.message,
    required this.sender,
    required this.own,
  });

  final TogetherMessage message;
  final String sender;
  final bool own;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: .42),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: own
                    ? AppColors.brandCyan.withValues(alpha: .20)
                    : Colors.white.withValues(alpha: .10),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 11, 8),
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.28,
                    fontFamily: 'Inter',
                    shadows: [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  children: [
                    TextSpan(
                      text: '$sender  ',
                      style: const TextStyle(
                        color: AppColors.brandCyan,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (message.isMoment && message.mediaPosition != null)
                      TextSpan(
                        text: 'Moment ${_time(message.mediaPosition!)} · ',
                        style: const TextStyle(
                          color: AppColors.brandYellow,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    TextSpan(
                      text: message.text,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return value.inHours > 0
        ? '${value.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

class _AmbientReaction extends StatelessWidget {
  const _AmbientReaction({
    super.key,
    required this.reaction,
    required this.index,
  });

  final String reaction;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .78, end: 1),
      duration: Duration(milliseconds: 220 + (index * 55)),
      curve: Curves.easeOutBack,
      builder: (_, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: .30),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Text(reaction, style: const TextStyle(fontSize: 23)),
      ),
    );
  }
}
