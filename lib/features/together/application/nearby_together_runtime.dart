import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/models/media_item.dart';
import '../../../core/services/otya_identity_service.dart';
import '../data/nearby_together_channel.dart';
import '../domain/media_identity.dart';
import '../domain/together_message.dart';
import '../domain/together_session.dart';
import 'media_kit_together_adapter.dart';
import 'nearby_together_session.dart';
import 'playback_sync_engine.dart';
import 'together_session_controller.dart';

enum NearbyTogetherRole { host, guest }

/// Process-local owner for one active Nearby Together room.
///
/// The runtime deliberately outlives the invite/scanner sheet so dismissing UI
/// never kills the peer session. It owns only Together resources and attaches
/// to the Player OTYA already created; normal local playback never depends on it.
class NearbyTogetherRuntime extends ChangeNotifier {
  NearbyTogetherRuntime._();

  static final instance = NearbyTogetherRuntime._();

  /// Keep reactions deliberately tiny and first-party. No sticker/image pack or
  /// chat SDK is needed for Together v1.
  static const Set<String> supportedReactions = {'❤️', '😂', '😮', '👏'};

  final TogetherSessionController _room = TogetherSessionController();

  NearbyTogetherHostSession? _host;
  NearbyTogetherGuestSession? _guest;
  NearbyTogetherRole? _role;
  NearbyPlaybackPlan? _guestPlan;
  MediaKitTogetherAdapter? _adapter;
  NearbyTogetherInvite? _invite;
  StreamSubscription<NearbyTogetherMessage>? _messageSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  Timer? _heartbeat;
  Timer? _clockTimer;

  String? _localParticipantId;
  String? _lastError;
  bool _starting = false;
  bool _hostMediaHandoffPending = false;

  TogetherSessionState get state => _room.state;
  NearbyTogetherInvite? get invite => _invite;
  NearbyPlaybackPlan? get guestPlan => _guestPlan;
  NearbyTogetherRole? get role => _role;
  String? get localParticipantId => _localParticipantId;
  String? get lastError => _lastError;
  bool get starting => _starting;
  bool get active => state.hasActiveSession;
  bool get isHost => _role == NearbyTogetherRole.host;
  bool get isGuest => _role == NearbyTogetherRole.guest;
  bool get guestStreaming =>
      isGuest && _guestPlan?.kind == NearbyPlaybackSourceKind.hostLanStream;

  Future<NearbyTogetherInvite> startHost({
    required MediaItem mediaItem,
    required Player player,
    String? displayName,
  }) async {
    _beginStart();
    try {
      await stop(notify: false);

      final username = await OtyaIdentityService.instance.cachedUsername();
      final host = NearbyTogetherHostSession();
      final resolvedName = _displayName(displayName, username);

      final invite = await host.start(
        filePath: mediaItem.filePath,
        displayName: resolvedName,
        username: username,
        duration: mediaItem.duration,
      );
      final media = host.mediaIdentity;
      if (media == null) {
        await host.dispose();
        throw StateError('OTYA could not identify this video for Together.');
      }

      _host = host;
      _role = NearbyTogetherRole.host;
      _invite = invite;
      _localParticipantId = _ephemeralId('host');

      final now = DateTime.now().toUtc();
      _room.start(
        TogetherSession(
          id: _ephemeralId('room'),
          hostParticipantId: _localParticipantId!,
          activeMediaFingerprint: media.fingerprint,
          phase: TogetherSessionPhase.connecting,
          participants: [
            TogetherParticipant(
              id: _localParticipantId!,
              displayName: resolvedName,
              username: username,
              role: TogetherParticipantRole.host,
              isConnected: true,
              joinedAt: now,
            ),
          ],
          createdAt: now,
        ),
      );

      _messageSub = host.channel.messages.listen(_handleGuestMessage);
      _connectionSub = host.channel.connected.listen(_handleHostConnection);
      _bindHostPlayer(player);
      _heartbeat = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => unawaited(_sendHostState()),
      );

      notifyListeners();
      return invite;
    } catch (error) {
      _lastError = _friendlyError(error);
      rethrow;
    } finally {
      _finishStart();
    }
  }

  /// Joins a Nearby Together room and decides whether this phone can play its
  /// own matching copy or needs the host's authenticated LAN Range source.
  ///
  /// When [kind] is [NearbyPlaybackSourceKind.hostLanStream], the caller should
  /// hand the returned URL into OTYA's player and then call [attachPlayer].
  Future<NearbyPlaybackPlan> joinGuest({
    required Uri inviteUri,
    required MediaItem candidateMediaItem,
    required Player player,
    String? displayName,
  }) async {
    _beginStart();
    try {
      await stop(notify: false);

      final username = await OtyaIdentityService.instance.cachedUsername();
      final resolvedName = _displayName(displayName, username);
      final guest = NearbyTogetherGuestSession();
      final plan = await guest.join(
        inviteUri: inviteUri,
        displayName: resolvedName,
        username: username,
        candidateLocalFilePath: candidateMediaItem.filePath,
        candidateDuration: candidateMediaItem.duration,
      );

      _guest = guest;
      _guestPlan = plan;
      _role = NearbyTogetherRole.guest;
      _localParticipantId = _ephemeralId('guest');

      final now = DateTime.now().toUtc();
      const hostId = 'nearby-host';
      _room.start(
        TogetherSession(
          id: _ephemeralId('room'),
          hostParticipantId: hostId,
          activeMediaFingerprint: plan.remoteMedia.fingerprint,
          phase: TogetherSessionPhase.watching,
          connectionPath: TogetherConnectionPath.nearby,
          participants: [
            TogetherParticipant(
              id: hostId,
              displayName: plan.hostDisplayName,
              username: plan.hostUsername,
              role: TogetherParticipantRole.host,
              isConnected: true,
              joinedAt: now,
            ),
            TogetherParticipant(
              id: _localParticipantId!,
              displayName: resolvedName,
              username: username,
              role: TogetherParticipantRole.guest,
              isConnected: true,
              joinedAt: now,
            ),
          ],
          createdAt: now,
        ),
      );

      _messageSub = guest.channel.messages.listen(_handleHostMessage);
      _connectionSub = guest.channel.connected.listen(_handleGuestConnection);
      if (plan.kind == NearbyPlaybackSourceKind.localCopy) {
        attachPlayer(player);
      }
      _clockTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_sendClockPing()),
      );
      unawaited(_sendClockPing());

      notifyListeners();
      return plan;
    } catch (error) {
      _lastError = _friendlyError(error);
      rethrow;
    } finally {
      _finishStart();
    }
  }

  /// Prepares a host-selected next video without replacing the Together room.
  /// The media sender rotates its file/token, the room revision advances, and
  /// the guest is told to switch its existing player. Heartbeats stay paused
  /// until the host's new local Player attaches after the route handoff.
  Future<void> prepareHostNextMedia(MediaItem mediaItem) async {
    final host = _host;
    final session = state.session;
    if (!isHost || host == null || session == null || !session.isActive) {
      throw StateError('Only an active Together host can choose the next video.');
    }
    if (_hostMediaHandoffPending) {
      throw StateError('Together is already changing video.');
    }

    _hostMediaHandoffPending = true;
    _lastError = null;
    try {
      await _adapter?.player.pause();
      final hosted = await host.switchMedia(
        filePath: mediaItem.filePath,
        duration: mediaItem.duration,
      );
      final now = DateTime.now().toUtc();
      _room.startNextMedia(hosted.media.fingerprint, now);
      final nextSession = state.session!;
      _adapter?.resetForMediaRevision(nextSession.mediaRevision);
      notifyListeners();

      if (host.channel.hasGuest) {
        try {
          await host.channel.send(
            'media',
            _mediaChangePayload(
              hosted.media,
              hosted.hostMediaUrl,
              nextSession.mediaRevision,
            ),
          );
        } catch (_) {
          // A disconnected guest must not prevent the host from moving on.
        }
      }
    } catch (error) {
      _hostMediaHandoffPending = false;
      _lastError = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  /// Attaches Together to an already-created OTYA Player. This is used for the
  /// initial local-copy path and later for a safe guest or host media handoff.
  void attachPlayer(Player player) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    if (_adapter?.player == player) return;

    _adapter = MediaKitTogetherAdapter(player: player)
      ..resetForMediaRevision(session.mediaRevision);
    if (isHost) {
      _bindHostPlayer(player, replaceAdapter: false);
      _hostMediaHandoffPending = false;
      unawaited(_sendHostState());
    }
    if (isGuest) unawaited(_sendClockPing());
    notifyListeners();
  }

  void detachPlayer(Player player) {
    if (_adapter?.player != player) return;
    _adapter = null;
    if (isHost) {
      unawaited(_playingSub?.cancel());
      unawaited(_completedSub?.cancel());
      _playingSub = null;
      _completedSub = null;
    }
  }

  Future<void> sendChat(String rawText) async {
    final text = rawText.trim();
    final session = state.session;
    final sender = _localParticipantId;
    if (session == null || sender == null || text.isEmpty) return;
    if (text.length > TogetherMessage.maxTextLength) {
      throw ArgumentError('Together messages are limited to ${TogetherMessage.maxTextLength} characters.');
    }

    final now = DateTime.now().toUtc();
    _room.receiveMessage(
      TogetherMessage(
        id: _ephemeralId('msg'),
        sessionId: session.id,
        senderParticipantId: sender,
        text: text,
        kind: TogetherMessageKind.text,
        createdAt: now,
      ),
      conversationVisible: true,
    );
    notifyListeners();
    await _sendPeer('chat', {'text': text});
  }

  Future<void> sendMoment(
    Duration position, {
    String text = 'Look at this moment',
  }) async {
    final session = state.session;
    final sender = _localParticipantId;
    if (session == null || sender == null) return;

    final now = DateTime.now().toUtc();
    final cleanText = text.trim().isEmpty ? 'Look at this moment' : text.trim();
    _room.receiveMessage(
      TogetherMessage(
        id: _ephemeralId('moment'),
        sessionId: session.id,
        senderParticipantId: sender,
        text: cleanText,
        kind: TogetherMessageKind.moment,
        mediaPosition: position,
        createdAt: now,
      ),
      conversationVisible: true,
    );
    notifyListeners();
    await _sendPeer('moment', {
      'text': cleanText,
      'position_ms': position.inMilliseconds,
    });
  }

  /// Creates a Moment at the position already owned by OTYA's single player.
  /// The Together UI never creates or reaches into a second media engine.
  Future<void> sendCurrentMoment({String text = 'Look at this moment'}) async {
    final player = _adapter?.player;
    if (player == null) return;
    await sendMoment(player.state.position, text: text);
  }

  Future<void> sendReaction(String rawReaction) async {
    final reaction = rawReaction.trim();
    final session = state.session;
    final sender = _localParticipantId;
    if (session == null || sender == null || reaction.isEmpty) return;
    if (!supportedReactions.contains(reaction)) {
      throw ArgumentError.value(
        rawReaction,
        'reaction',
        'Unsupported Together reaction',
      );
    }

    final now = DateTime.now().toUtc();
    _room.receiveMessage(
      TogetherMessage(
        id: _ephemeralId('reaction'),
        sessionId: session.id,
        senderParticipantId: sender,
        text: reaction,
        kind: TogetherMessageKind.reaction,
        createdAt: now,
      ),
      conversationVisible: true,
    );
    notifyListeners();
    await _sendPeer('reaction', {'reaction': reaction});
  }

  void markConversationRead() {
    _room.markConversationRead();
    notifyListeners();
  }

  Future<void> stop({bool notify = true}) async {
    _heartbeat?.cancel();
    _clockTimer?.cancel();
    _heartbeat = null;
    _clockTimer = null;
    await _messageSub?.cancel();
    await _connectionSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    _messageSub = null;
    _connectionSub = null;
    _playingSub = null;
    _completedSub = null;

    final host = _host;
    final guest = _guest;
    _host = null;
    _guest = null;
    _role = null;
    _guestPlan = null;
    _adapter = null;
    _invite = null;
    _localParticipantId = null;
    _hostMediaHandoffPending = false;
    if (host != null) await host.dispose();
    if (guest != null) await guest.dispose();

    if (_room.state.session != null) {
      _room.close(DateTime.now().toUtc());
      _room.clearClosedRoom();
    }
    if (notify) notifyListeners();
  }

  void _bindHostPlayer(Player player, {bool replaceAdapter = true}) {
    if (replaceAdapter) {
      final session = state.session;
      _adapter = MediaKitTogetherAdapter(player: player);
      if (session != null) _adapter!.resetForMediaRevision(session.mediaRevision);
    }
    unawaited(_playingSub?.cancel());
    unawaited(_completedSub?.cancel());
    _playingSub = player.stream.playing.listen((_) => unawaited(_sendHostState()));
    _completedSub = player.stream.completed.listen((completed) {
      if (!completed || !state.hasActiveSession) return;
      try {
        _room.playbackEnded(DateTime.now().toUtc());
        notifyListeners();
        unawaited(_sendHostState());
      } catch (_) {}
    });
  }

  void _handleHostConnection(bool connected) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    final now = DateTime.now().toUtc();
    const guestId = 'nearby-guest';
    final existing = session.participants.where((item) => item.id == guestId).firstOrNull;

    try {
      if (connected) {
        _room.addParticipant(
          existing?.copyWith(isConnected: true) ??
              TogetherParticipant(
                id: guestId,
                displayName: 'Nearby guest',
                role: TogetherParticipantRole.guest,
                isConnected: true,
                joinedAt: now,
              ),
          now,
        );
        _room.connected(TogetherConnectionPath.nearby, now);
        unawaited(_sendHostState());
      } else {
        if (existing != null) {
          _room.addParticipant(existing.copyWith(isConnected: false), now);
        }
        _room.reconnecting(now);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _handleGuestConnection(bool connected) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    final host = session.participants
        .where((item) => item.role == TogetherParticipantRole.host)
        .firstOrNull;
    final now = DateTime.now().toUtc();
    try {
      if (host != null) {
        _room.addParticipant(host.copyWith(isConnected: connected), now);
      }
      if (connected) {
        _room.connected(TogetherConnectionPath.nearby, now);
        unawaited(_sendClockPing());
      } else {
        _room.reconnecting(now);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _handleGuestMessage(NearbyTogetherMessage message) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    const guestId = 'nearby-guest';

    switch (message.type) {
      case 'ready':
        final name = _text(message.payload['display_name']) ?? 'Nearby guest';
        final username = _text(message.payload['username'])
            ?.replaceFirst(RegExp(r'^@+'), '')
            .toLowerCase();
        try {
          _room.addParticipant(
            TogetherParticipant(
              id: guestId,
              displayName: name,
              username: username,
              role: TogetherParticipantRole.guest,
              isConnected: true,
              joinedAt: message.sentAt,
            ),
            message.sentAt,
          );
          _room.connected(TogetherConnectionPath.nearby, message.sentAt);
          notifyListeners();
        } catch (_) {}
        break;
      case 'chat':
        _receivePeerText(message, guestId, TogetherMessageKind.text);
        break;
      case 'moment':
        _receivePeerMoment(message, guestId);
        break;
      case 'reaction':
        _receivePeerReaction(message, guestId);
        break;
      case 'ping':
        final host = _host;
        final adapter = _adapter;
        if (host != null && adapter != null) {
          unawaited(host.channel.send('pong', {
            'guest_send_us': message.payload['guest_send_us'],
            'host_reply_us': adapter.monotonicClock.elapsedMicroseconds,
          }).catchError((_) {}));
        }
        break;
      case 'bye':
        _handleHostConnection(false);
        break;
    }
  }

  void _handleHostMessage(NearbyTogetherMessage message) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    const hostId = 'nearby-host';

    switch (message.type) {
      case 'state':
        final remote = TogetherPlaybackState.tryParse(message.payload);
        final adapter = _adapter;
        if (remote != null && adapter != null) {
          unawaited(adapter.applyRemoteState(remote));
        }
        break;
      case 'media':
        unawaited(_handleGuestMediaChange(message));
        break;
      case 'chat':
        _receivePeerText(message, hostId, TogetherMessageKind.text);
        break;
      case 'moment':
        _receivePeerMoment(message, hostId);
        break;
      case 'reaction':
        _receivePeerReaction(message, hostId);
        break;
      case 'pong':
        final guestSendUs = message.payload['guest_send_us'];
        final hostReplyUs = message.payload['host_reply_us'];
        final adapter = _adapter;
        if (guestSendUs is int && hostReplyUs is int && adapter != null) {
          adapter.addClockSample(
            TogetherClockSample(
              guestSendUs: guestSendUs,
              hostReplyUs: hostReplyUs,
              guestReceiveUs: adapter.monotonicClock.elapsedMicroseconds,
            ),
          );
        }
        break;
      case 'bye':
        _handleGuestConnection(false);
        break;
    }
  }

  Future<void> _handleGuestMediaChange(NearbyTogetherMessage message) async {
    final guest = _guest;
    final session = state.session;
    final revision = message.payload['media_revision'];
    if (guest == null ||
        session == null ||
        !session.isActive ||
        revision is! int ||
        revision <= session.mediaRevision) {
      return;
    }
    if (revision != session.mediaRevision + 1) {
      _lastError = 'Together changed video out of sequence. Reconnect to the host.';
      try {
        _room.reconnecting(message.sentAt);
      } catch (_) {}
      notifyListeners();
      return;
    }

    try {
      final plan = await guest.planMediaChange(message);
      final uri = plan.hostMediaUrl;
      final adapter = _adapter;
      if (uri == null || adapter == null) {
        throw StateError('Together player is not ready for the next video.');
      }

      _room.startNextMedia(plan.remoteMedia.fingerprint, message.sentAt);
      final updated = state.session!;
      if (updated.mediaRevision != revision) {
        throw StateError('Together media revision mismatch.');
      }
      _guestPlan = plan;
      _lastError = null;
      adapter.resetForMediaRevision(revision);
      notifyListeners();

      await adapter.player.pause();
      await adapter.player.open(Media(uri.toString()), play: false);
      unawaited(_sendClockPing());
    } catch (error) {
      _lastError = _friendlyError(error);
      try {
        _room.reconnecting(DateTime.now().toUtc());
      } catch (_) {}
      notifyListeners();
    }
  }

  void _receivePeerText(
    NearbyTogetherMessage message,
    String senderId,
    TogetherMessageKind kind,
  ) {
    final session = state.session;
    final text = _text(message.payload['text']);
    if (session == null || text == null || text.length > TogetherMessage.maxTextLength) return;
    _room.receiveMessage(
      TogetherMessage(
        id: message.id,
        sessionId: session.id,
        senderParticipantId: senderId,
        text: text,
        kind: kind,
        createdAt: message.sentAt,
      ),
      conversationVisible: false,
    );
    notifyListeners();
  }

  void _receivePeerMoment(NearbyTogetherMessage message, String senderId) {
    final session = state.session;
    final text = _text(message.payload['text']) ?? 'Look at this moment';
    final positionMs = message.payload['position_ms'];
    if (session == null || positionMs is! int || positionMs < 0) return;
    _room.receiveMessage(
      TogetherMessage(
        id: message.id,
        sessionId: session.id,
        senderParticipantId: senderId,
        text: text,
        kind: TogetherMessageKind.moment,
        mediaPosition: Duration(milliseconds: positionMs),
        createdAt: message.sentAt,
      ),
      conversationVisible: false,
    );
    notifyListeners();
  }

  void _receivePeerReaction(NearbyTogetherMessage message, String senderId) {
    final session = state.session;
    final reaction = _text(message.payload['reaction']);
    if (session == null ||
        reaction == null ||
        !supportedReactions.contains(reaction)) {
      return;
    }
    _room.receiveMessage(
      TogetherMessage(
        id: message.id,
        sessionId: session.id,
        senderParticipantId: senderId,
        text: reaction,
        kind: TogetherMessageKind.reaction,
        createdAt: message.sentAt,
      ),
      conversationVisible: false,
    );
    notifyListeners();
  }

  Future<void> _sendHostState() async {
    final host = _host;
    final adapter = _adapter;
    final session = state.session;
    if (host == null ||
        adapter == null ||
        session == null ||
        !session.isActive ||
        !host.channel.hasGuest ||
        _hostMediaHandoffPending ||
        adapter.applyingRemote) {
      return;
    }

    try {
      await host.channel.send(
        'state',
        adapter.captureHostState(mediaRevision: session.mediaRevision).toJson(),
      );
    } catch (_) {
      // A heartbeat failure must never interrupt local playback.
    }
  }

  Future<void> _sendClockPing() async {
    final guest = _guest;
    final adapter = _adapter;
    if (guest == null || adapter == null || !state.hasActiveSession) return;
    try {
      await guest.channel.send('ping', {
        'guest_send_us': adapter.monotonicClock.elapsedMicroseconds,
      });
    } catch (_) {}
  }

  Future<void> _sendPeer(String type, Map<String, dynamic> payload) async {
    final host = _host;
    if (host != null) {
      await host.channel.send(type, payload);
      return;
    }
    final guest = _guest;
    if (guest != null) {
      await guest.channel.send(type, payload);
    }
  }

  static Map<String, dynamic> _mediaChangePayload(
    OtyaMediaIdentity media,
    Uri hostMediaUrl,
    int mediaRevision,
  ) => {
        'media_revision': mediaRevision,
        'media': {
          'fingerprint': media.fingerprint,
          'byte_length': media.byteLength,
          if (media.duration != null) 'duration_ms': media.duration!.inMilliseconds,
          if (media.mimeType != null) 'mime_type': media.mimeType,
        },
        'media_url': hostMediaUrl.toString(),
      };

  void _beginStart() {
    if (_starting) throw StateError('Together is already starting.');
    _starting = true;
    _lastError = null;
    notifyListeners();
  }

  void _finishStart() {
    _starting = false;
    notifyListeners();
  }

  static String _displayName(String? displayName, String? username) {
    if (displayName?.trim().isNotEmpty == true) return displayName!.trim();
    if (username?.isNotEmpty == true) return '@$username';
    return 'OTYA user';
  }

  static String _ephemeralId(String prefix) {
    final rng = Random.secure();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${rng.nextInt(0x7fffffff).toRadixString(36)}';
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('Wi-Fi') ||
        message.contains('hotspot') ||
        message.contains('timed out')) {
      return 'Keep both phones on the same Wi-Fi or hotspot, then try again.';
    }
    if (message.contains('not found') || message.contains('empty')) {
      return 'That video is no longer available on this device.';
    }
    if (message.contains('invalid Nearby Together invite')) {
      return 'That Together invite is not valid anymore. Ask the host to show a new one.';
    }
    if (message.contains('next video') || message.contains('media revision')) {
      return 'OTYA could not switch the Together video. Keep the room open and try again.';
    }
    return 'OTYA could not connect Together. Check the local connection and try again.';
  }
}
