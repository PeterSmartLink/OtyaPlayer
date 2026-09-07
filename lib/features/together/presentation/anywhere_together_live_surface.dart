import 'package:flutter/material.dart';

import '../application/anywhere_together_runtime.dart';
import 'together_live_surface.dart';

Future<void> showAnywhereTogetherLiveRoomSurface({
  required BuildContext context,
  required AnywhereTogetherRuntime runtime,
  required ValueChanged<Duration> onMomentTap,
  required VoidCallback onInvite,
  required VoidCallback onLeave,
  VoidCallback? onReplay,
}) {
  return showTogetherLiveRoomSurface(
    context: context,
    listenable: runtime,
    session: () => runtime.state.session,
    messages: () => runtime.state.messages,
    localParticipantId: () => runtime.localParticipantId,
    sendChat: runtime.sendChat,
    sendCurrentMoment: runtime.sendCurrentMoment,
    sendReaction: runtime.sendReaction,
    markConversationRead: runtime.markConversationRead,
    reactions: AnywhereTogetherRuntime.supportedReactions,
    onMomentTap: onMomentTap,
    onInvite: onInvite,
    onLeave: onLeave,
    onReplay: onReplay,
  );
}
