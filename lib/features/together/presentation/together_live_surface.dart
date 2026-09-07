import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../domain/together_message.dart';
import '../domain/together_session.dart';
import 'together_surface.dart';

/// Shared reactive Together conversation surface used by every connection path.
///
/// Nearby and Anywhere supply different transports, but the person watching a
/// movie sees one OTYA room: the same conversation, Moments, reactions and
/// After Watch lifecycle over the existing player.
Future<void> showTogetherLiveRoomSurface({
  required BuildContext context,
  required Listenable listenable,
  required TogetherSession? Function() session,
  required List<TogetherMessage> Function() messages,
  required String? Function() localParticipantId,
  required Future<void> Function(String text) sendChat,
  required Future<void> Function() sendCurrentMoment,
  required Future<void> Function(String reaction) sendReaction,
  required VoidCallback markConversationRead,
  required Iterable<String> reactions,
  required ValueChanged<Duration> onMomentTap,
  required VoidCallback onInvite,
  required VoidCallback onLeave,
  VoidCallback? onReplay,
  VoidCallback? onChooseNext,
}) async {
  final initialSession = session();
  final initialLocalId = localParticipantId();
  if (initialSession == null ||
      initialLocalId == null ||
      !initialSession.isActive) {
    return;
  }

  final supportedReactions = reactions.toList(growable: false);
  final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

  Widget liveContent(BuildContext surfaceContext) => AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          final currentSession = session();
          final localId = localParticipantId();
          if (currentSession == null ||
              localId == null ||
              !currentSession.isActive) {
            return const _TogetherEndedView();
          }
          return Column(
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: TogetherRoomContent(
                    session: currentSession,
                    messages: messages(),
                    localParticipantId: localId,
                    onSendMessage: (text) => unawaited(sendChat(text)),
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
                reactions: supportedReactions,
                momentEnabled:
                    currentSession.phase == TogetherSessionPhase.watching,
                onMoment: () => unawaited(sendCurrentMoment()),
                onReaction: (reaction) => unawaited(sendReaction(reaction)),
              ),
            ],
          );
        },
      );

  markConversationRead();
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
        final maxPanel = availableHeight * .82;
        final panelHeight = _boundedExtent(
          desired: availableHeight * factor,
          maximum: maxPanel,
          preferredMinimum: 300,
        );

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
        final height = _boundedExtent(
          desired: availableHeight * heightFactor,
          maximum: availableHeight,
          preferredMinimum: 250,
        );

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
  markConversationRead();
}

double _boundedExtent({
  required double desired,
  required double maximum,
  required double preferredMinimum,
}) {
  final safeMaximum = maximum > 1 ? maximum : 1.0;
  final safeMinimum =
      preferredMinimum < safeMaximum ? preferredMinimum : safeMaximum;
  return desired.clamp(safeMinimum, safeMaximum).toDouble();
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
    final baseTheme = Theme.of(context);
    final glassScheme = baseTheme.colorScheme.copyWith(
      surfaceContainerHighest:
          AppColors.surfaceElevated.withValues(alpha: .48),
      surfaceContainerHigh: AppColors.surfaceElevated.withValues(alpha: .42),
      surfaceContainer: AppColors.surface.withValues(alpha: .38),
    );

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
          child: Theme(
            data: baseTheme.copyWith(
              colorScheme: glassScheme,
              inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
                fillColor: AppColors.surfaceElevated.withValues(alpha: .42),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TogetherQuickActions extends StatelessWidget {
  final List<String> reactions;
  final bool momentEnabled;
  final VoidCallback onMoment;
  final ValueChanged<String> onReaction;

  const _TogetherQuickActions({
    required this.reactions,
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
            for (final reaction in reactions)
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
