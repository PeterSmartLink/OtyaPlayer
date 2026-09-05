# OTYA New Way

OTYA must feel like one media application, not a collection of separate apps.

## Product identity

**OTYA**

**Play. Send. Together.**

The user always starts from their media. Play, Send, and Together are contextual actions around the same song or video.

## Non-negotiable product rules

1. Local video and music playback must work without internet and without an account.
2. Nearby transfer must work without internet and without an account.
3. Together is optional. A Together failure must never break local playback.
4. Do not add a Together, Chat, Friends, or Transfer main-navigation tab.
5. Keep the current primary experience centered on Video, Music, and Me.
6. Together chat exists only inside a Together session in v1; OTYA is not a general messaging app.
7. The video viewport must not be permanently resized by chat or participant UI.
8. Mini-player and Picture-in-Picture remain media-first; social UI is reduced or absent there.
9. One media engine only. Do not add another video player just for Together.
10. New native dependencies require an APK-size and reliability benchmark before adoption.

## Size budget

The current per-ABI Android release is roughly in the low-20 MB range. The new direction should preserve that advantage.

- Preferred ARM64 release target: under 30 MB.
- Review/warning line: 35 MB.
- Hard ceiling: 40 MB.
- Do not add a second media engine, a full chat SDK, a second analytics SDK, or large reaction/image packs.
- Text chat, session models, reactions, and UI should remain first-party and lightweight.
- The P2P transport must be benchmarked separately before being accepted.

## One-app interaction model

A media item has contextual capabilities:

- **Play** — local playback.
- **Send** — nearby direct transfer when possible.
- **Together** — synchronized shared playback, selecting the best available peer path.

Users never choose technical modes such as LAN, WebRTC, DataChannel, STUN, TURN, or offline/online mode. OTYA selects the path.

## Together lifecycle

A Together session moves through:

1. Creating
2. Connecting
3. Watching
4. After Watch
5. Reconnecting when needed
6. Closed

When a movie ends, the room does not close immediately. It enters **After Watch** so participants can discuss the ending, replay, or choose the next video. The initial policy keeps an idle room alive for a short period (currently 10 minutes) before cleanup.

If the host chooses another video, the same participants and conversation continue inside the same Together session.

When the room closes:

- Stream-only temporary media is deleted.
- A user-requested saved transfer may be preserved/resumed according to transfer policy.
- Ephemeral Together conversation is removed in v1.
- Local playback remains unaffected.

## Identity

Connected OTYA accounts may use:

- display name
- unique username such as `@peter`
- optional avatar

Username is for connected identity, invitations, moderation, and Together. It must not become a requirement for opening OTYA or playing/sending media nearby.

Nearby Together may use a cached account identity or a temporary local display name when no account is available.

## Conversation

Together conversation is session-scoped and intentionally small:

- text
- replies later if needed
- a small reaction set
- **Moment messages** tied to a playback position

A Moment message can reference a timestamp such as `01:18:42`, allowing participants to return to or request that moment.

Conversation UI is contextual:

- portrait: temporary bottom sheet/overlay
- landscape/full screen: temporary side overlay
- mini-player: unread indicator only
- PiP: no chat surface
- locked controls: Together controls remain locked

## Media identity

OTYA should identify media independently from filenames and local paths using a privacy-preserving media fingerprint.

This allows OTYA to determine whether another peer:

- already has the complete media — send synchronization/control only
- has part of it — request only missing byte ranges
- has none — stream requested ranges

The exact fingerprint algorithm must be benchmarked for collision resistance, speed, battery cost, and privacy before implementation.

## Transport strategy

Nearby and remote experiences share a common media-transfer contract but use different transports.

- Nearby: local Wi-Fi/hotspot/direct local peer path, no internet required.
- Remote: direct internet P2P where possible.
- Relay: optional encrypted relay fallback only when product policy allows it.

Together should reuse file-range, resume, integrity, caching, and save logic rather than duplicating separate implementations.

## V1 scope

Build the smallest excellent version first:

- one host + one guest
- private session
- local video
- nearby Together without internet
- remote Together over the internet
- synchronized play/pause/seek
- lightweight text conversation
- Moment messages
- small reactions
- stream only
- optional stream-and-save
- reconnect/recovery
- After Watch state

Do not add public rooms, social feeds, stories, followers, general direct messaging, or large group rooms in v1.

## Architecture boundary

Together depends on the player and media core. The player and media core must never depend on Together.

That boundary is the main protection for OTYA's offline-first reliability.
