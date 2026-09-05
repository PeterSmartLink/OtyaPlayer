import 'dart:async';

import 'package:flutter/material.dart';

import '../application/nearby_together_runtime.dart';
import '../domain/together_session.dart';
import 'together_surface.dart';

/// Live Nearby Together room surface.
///
/// [TogetherRoomContent] remains the single conversation presentation. This
/// wrapper only binds it to the process-local Nearby runtime so participants,
/// messages and reconnect state repaint while the modal remains open.
Future<void> showNearbyTogetherLiveRoomSurface({
  required BuildContext context,
  required NearbyTogetherRuntime runtime,
  required ValueChanged<Duration> onMomentTap,
  required VoidCallback onInvite,
  required VoidCallback onLeave,
  VoidCallback? onReplay,
  VoidCallback? onChooseNext,
}) async {
  final initialSession = runtime.state.session;
  final initialLocalId = runtime.localParticipantId;
  if (initialSession == null ||
      initialLocalId == null ||
      !initialSession.isActive) {
    return;
  }

  final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

  Widget liveContent(BuildContext surfaceContext) => AnimatedBuilder(
        animation: runtime,
        builder: (context, _) {
          final session = runtime.state.session;
          final localId = runtime.localParticipantId;
          if (session == null || localId == null || !session.isActive) {
            return const _TogetherEndedView();
          }
          return Column(
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: TogetherRoomContent(
                    session: session,
                    messages: runtime.state.messages,
                    localParticipantId: localId,
                    onSendMessage: (text) => unawaited(runtime.sendChat(text)),
                    onMomentTap: onMomentTap,
                    onInvite: onInvite,
                    onLeave: onLeave,
                    onReplay: onReplay,
                    onChooseNext: onChooseNext,
                    onClose: () => Navigator.of(surfaceContext).pop(),
                  ),
                ),
              ),
              _TogetherQuickActions(
                momentEnabled: session.phase == TogetherSessionPhase.watching,
                onMoment: () => unawaited(runtime.sendCurrentMoment()),
                onReaction: (reaction) =>
                    unawaited(runtime.sendReaction(reaction)),
              ),
            ],
          );
        },
      );

  runtime.markConversationRead();
  if (!landscape) {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor:
          Theme.of(context).colorScheme.surface.withValues(alpha: .98),
      barrierColor: Colors.black.withValues(alpha: .30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .64,
        child: liveContent(sheetContext),
      ),
    );
  } else {
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
            color: Theme.of(dialogContext)
                .colorScheme
                .surface
                .withValues(alpha: .96),
            elevation: 18,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: MediaQuery.sizeOf(dialogContext)
                  .width
                  .clamp(320, 430)
                  .toDouble(),
              height: double.infinity,
              child: liveContent(dialogContext),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }
  runtime.markConversationRead();
}

class _TogetherQuickActions extends StatelessWidget {
  final bool momentEnabled;
  final VoidCallback onMoment;
  final ValueChanged<String> onReaction;

  const _TogetherQuickActions({
    required this.momentEnabled,
    required this.onMoment,
    required this.onReaction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 4, 8, 5),
        child: Row(
          children: [
            Tooltip(
              message: 'Share this playback position',
              child: TextButton.icon(
                onPressed: momentEnabled ? onMoment : null,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Moment'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const Spacer(),
            for (final reaction in NearbyTogetherRuntime.supportedReactions)
              _ReactionButton(
                reaction: reaction,
                onPressed: () => onReaction(reaction),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String reaction;
  final VoidCallback onPressed;

  const _ReactionButton({
    required this.reaction,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'React $reaction',
      child: Tooltip(
        message: 'React $reaction',
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: SizedBox(
            width: 42,
            height: 44,
            child: Center(
              child: Text(
                reaction,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TogetherEndedView extends StatelessWidget {
  const _TogetherEndedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 34,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            const Text(
              'Together ended',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Your normal Otya playback remains available.',
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
