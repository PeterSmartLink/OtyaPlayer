import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../application/nearby_together_runtime.dart';
import '../domain/together_session.dart';
import 'together_surface.dart';

/// Live Together conversation shown over the playing video.
///
/// This is deliberately not a second opaque "chat screen". Portrait uses a
/// compact bottom glass panel; landscape uses a floating right-side panel. The
/// keyboard is allowed to grow the surface only while the user is typing.
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
                    onSendMessage: (text) =>
                        unawaited(runtime.sendChat(text)),
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
                momentEnabled:
                    session.phase == TogetherSessionPhase.watching,
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .08),
      elevation: 0,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final availableHeight =
            media.size.height - media.viewInsets.bottom - media.padding.top;
        final keyboardOpen = media.viewInsets.bottom > 0;
        final baseFactor = media.size.height < 680 ? .56 : .48;
        final factor = keyboardOpen ? .72 : baseFactor;
        final panelHeight = (availableHeight * factor)
            .clamp(300.0, availableHeight * .82)
            .toDouble();

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            10,
            0,
            10,
            media.viewInsets.bottom > 0 ? 6 : 10,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: panelHeight,
              width: double.infinity,
              child: _TogetherGlassPanel(
                borderRadius: BorderRadius.circular(26),
                child: liveContent(sheetContext),
              ),
            ),
          ),
        );
      },
    );
  } else {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Together',
      barrierColor: Colors.black.withValues(alpha: .05),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        final media = MediaQuery.of(dialogContext);
        final keyboardOpen = media.viewInsets.bottom > 0;
        final availableHeight =
            media.size.height - media.padding.vertical - media.viewInsets.bottom;
        final width = (media.size.width * .36).clamp(300.0, 390.0).toDouble();
        final heightFactor = keyboardOpen ? .90 : .78;
        final height =
            (availableHeight * heightFactor).clamp(250.0, availableHeight).toDouble();

        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(
              10,
              10,
              12,
              media.viewInsets.bottom > 0 ? 6 : 12,
            ),
            child: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: width,
                height: height,
                child: _TogetherGlassPanel(
                  borderRadius: BorderRadius.circular(24),
                  child: liveContent(dialogContext),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.04, .04),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }
  runtime.markConversationRead();
}

class _TogetherGlassPanel extends StatelessWidget {
  final BorderRadius borderRadius;
  final Widget child;

  const _TogetherGlassPanel({
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.surfaceElevated.withValues(alpha: .72),
                AppColors.surface.withValues(alpha: .58),
                AppColors.brandDeepBlue.withValues(alpha: .16),
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: AppColors.brandCyan.withValues(alpha: .18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .20),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
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
        color: AppColors.surface.withValues(alpha: .18),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .34),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(8, 3, 8, 4),
        child: Row(
          children: [
            Tooltip(
              message: 'Share this playback position',
              child: TextButton.icon(
                onPressed: momentEnabled ? onMoment : null,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Moment'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 42),
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
            width: 40,
            height: 42,
            child: Center(
              child: Text(
                reaction,
                style: const TextStyle(fontSize: 19),
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
