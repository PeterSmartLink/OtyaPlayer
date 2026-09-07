import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/models/media_item.dart';
import '../data/anywhere_together_media_bridge.dart';
import '../data/anywhere_together_peer.dart';
import '../data/anywhere_together_protocol.dart';
import '../data/media_fingerprint_service.dart';
import '../data/together_control_client.dart';
import '../domain/together_message.dart';
import '../domain/together_session.dart';
import 'media_kit_together_adapter.dart';
import 'playback_sync_engine.dart';
import 'together_session_controller.dart';

class AnywhereTogetherInvite {
  final String roomId;
  final String inviteToken;
  final String guestUsername;
  final DateTime? expiresAt;

  const AnywhereTogetherInvite({
    required this.roomId,
    required this.inviteToken,
    required this.guestUsername,
    this.expiresAt,
  });
}

enum AnywherePlaybackSourceKind { localCopy, hostPeerStream }

class AnywherePlaybackPlan {
  final AnywherePlaybackSourceKind kind;
  final AnywhereMediaDescriptor remoteMedia;
  final String hostDisplayName;
  final String hostUsername;
  final Uri? hostMediaUrl;

  const AnywherePlaybackPlan({
    required this.kind,
    required this.remoteMedia,
    required this.hostDisplayName,
    required this.hostUsername,
    this.hostMediaUrl,
  });
}

/// Process-local owner for one active internet/Anywhere Together room.
///
/// Like NearbyTogetherRuntime, this object outlives invite/join sheets and
/// attaches only to the Player OTYA already owns. Local playback never depends
/// on WebRTC and Nearby Together never depends on this runtime.
class AnywhereTogetherRuntime extends ChangeNotifier {
  AnywhereTogetherRuntime._();

  static final instance = AnywhereTogetherRuntime._();
  static const Set<String> supportedReactions = {'❤️', '😂', '😮', '👏'};

  final TogetherSessionController _room = TogetherSessionController();
  final Random _random = Random.secure();

  AnywhereTogetherPeer? _peer;
  AnywhereTogetherMediaHost? _mediaHost;
  AnywhereTogetherMediaGuest? _mediaGuest;
  AnywhereTogetherInvite? _invite;
  AnywherePlaybackPlan? _guestPlan;
  AnywhereMediaDescriptor? _descriptor;
  MediaKitTogetherAdapter? _adapter;
  StreamSubscription<AnywhereTogetherPacket>? _packetSub;
  StreamSubscription<AnywhereTogetherPeerState>? _peerStateSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  Timer? _heartbeat;
  Timer? _clockTimer;
  Completer<AnywhereMediaDescriptor>? _descriptorCompleter;

  String? _localParticipantId;
  String? _lastError;
  bool _starting = false;

  TogetherSessionState get state => _room.state;
  AnywhereTogetherInvite? get invite => _invite;
  AnywherePlaybackPlan? get guestPlan => _guestPlan;
  AnywhereTogetherRole? get role => _peer?.role;
  String? get localParticipantId => _localParticipantId;
  String? get lastError => _lastError;
  bool get starting => _starting;
  bool get active => state.hasActiveSession;
  bool get isHost => role == AnywhereTogetherRole.host;
  bool get isGuest => role == AnywhereTogetherRole.guest;
  bool get guestStreaming =>
      isGuest && _guestPlan?.kind == AnywherePlaybackSourceKind.hostPeerStream;

  Future<AnywhereTogetherInvite> startHost({
    required MediaItem mediaItem,
    required Player player,
    required String inviteUsername,
  }) async {
    _beginStart();
    try {
      await stop(notify: false);
      final identity = await MediaFingerprintService.instance.identify(
        filePath: mediaItem.filePath,
        duration: mediaItem.duration,
        mimeType: _mimeType(mediaItem.fileName),
      );
      final descriptor = AnywhereMediaDescriptor(
        fingerprint: identity.fingerprint,
        byteLength: identity.byteLength,
        durationMs: (identity.duration ?? Duration.zero).inMilliseconds,
        mimeType: identity.mimeType,
      );

      final created = await TogetherControlClient.instance.createRoom(
        inviteUsername,
      );
      final creation = created.value;
      if (!created.ok || creation == null) {
        throw StateError(created.error ?? 'Could not create Anywhere Together.');
      }

      final peer = AnywhereTogetherPeer(
        roomId: creation.room.roomId,
        role: AnywhereTogetherRole.host,
      );
      final mediaHost = AnywhereTogetherMediaHost(peer: peer);
      await mediaHost.start(File(mediaItem.filePath));

      _peer = peer;
      _mediaHost = mediaHost;
      _descriptor = descriptor;
      _localParticipantId = _participantId(
        creation.room.host,
        fallback: 'anywhere-host',
      );
      _invite = AnywhereTogetherInvite(
        roomId: creation.room.roomId,
        inviteToken: creation.inviteToken,
        guestUsername: creation.room.guest.username,
        expiresAt: creation.room.expiresAt,
      );

      final now = DateTime.now().toUtc();
      _room.start(
        TogetherSession(
          id: creation.room.roomId,
          hostParticipantId: _localParticipantId!,
          activeMediaFingerprint: descriptor.fingerprint,
          phase: TogetherSessionPhase.connecting,
          participants: [
            _participant(
              creation.room.host,
              role: TogetherParticipantRole.host,
              connected: true,
              now: now,
            ),
            _participant(
              creation.room.guest,
              role: TogetherParticipantRole.guest,
              connected: false,
              now: now,
            ),
          ],
          createdAt: creation.room.createdAt ?? now,
        ),
      );

      _attachPeer(peer);
      attachPlayer(player);
      _heartbeat = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => unawaited(_sendHostState()),
      );
      unawaited(_connectHost(peer));
      notifyListeners();
      return _invite!;
    } catch (error) {
      _lastError = _friendlyError(error);
      rethrow;
    } finally {
      _finishStart();
    }
  }

  /// Joins an authenticated private room. When [candidateMediaItem] matches the
  /// host fingerprint exactly, OTYA reuses the local copy. Otherwise the caller
  /// receives a loopback URL backed by encrypted peer byte-range requests and
  /// should open that URL in the existing Player before calling [attachPlayer].
  Future<AnywherePlaybackPlan> joinGuest({
    required String roomId,
    required String inviteToken,
    required Player player,
    MediaItem? candidateMediaItem,
  }) async {
    _beginStart();
    try {
      await stop(notify: false);
      final joined = await TogetherControlClient.instance.joinRoom(
        roomId: roomId,
        inviteToken: inviteToken,
      );
      final remoteRoom = joined.value;
      if (!joined.ok || remoteRoom == null) {
        throw StateError(joined.error ?? 'Could not join Anywhere Together.');
      }

      final peer = AnywhereTogetherPeer(
        roomId: remoteRoom.roomId,
        role: AnywhereTogetherRole.guest,
      );
      _peer = peer;
      _localParticipantId = _participantId(
        remoteRoom.guest,
        fallback: 'anywhere-guest',
      );
      _descriptorCompleter = Completer<AnywhereMediaDescriptor>();
      _attachPeer(peer);

      await peer.connect();
      await _waitUntilConnected(peer);
      final descriptor = await _waitForDescriptor();
      _descriptor = descriptor;

      final now = DateTime.now().toUtc();
      _room.start(
        TogetherSession(
          id: remoteRoom.roomId,
          hostParticipantId: _participantId(
            remoteRoom.host,
            fallback: 'anywhere-host',
          ),
          activeMediaFingerprint: descriptor.fingerprint,
          phase: TogetherSessionPhase.watching,
          connectionPath: TogetherConnectionPath.internet,
          participants: [
            _participant(
              remoteRoom.host,
              role: TogetherParticipantRole.host,
              connected: true,
              now: now,
            ),
            _participant(
              remoteRoom.guest,
              role: TogetherParticipantRole.guest,
              connected: true,
              now: now,
            ),
          ],
          createdAt: remoteRoom.createdAt ?? now,
        ),
      );

      final localMatch = await _matchesLocalCandidate(
        candidateMediaItem,
        descriptor,
      );
      late final AnywherePlaybackPlan plan;
      if (localMatch) {
        plan = AnywherePlaybackPlan(
          kind: AnywherePlaybackSourceKind.localCopy,
          remoteMedia: descriptor,
          hostDisplayName: _displayName(remoteRoom.host),
          hostUsername: remoteRoom.host.username,
        );
        attachPlayer(player);
      } else {
        final mediaGuest = AnywhereTogetherMediaGuest(
          peer: peer,
          descriptor: descriptor,
        );
        final url = await mediaGuest.start();
        _mediaGuest = mediaGuest;
        plan = AnywherePlaybackPlan(
          kind: AnywherePlaybackSourceKind.hostPeerStream,
          remoteMedia: descriptor,
          hostDisplayName: _displayName(remoteRoom.host),
          hostUsername: remoteRoom.host.username,
          hostMediaUrl: url,
        );
      }
      _guestPlan = plan;
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

  void attachPlayer(Player player) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    if (_adapter?.player == player) return;

    _adapter = MediaKitTogetherAdapter(player: player)
      ..resetForMediaRevision(session.mediaRevision);
    if (isHost) _bindHostPlayer(player, replaceAdapter: false);
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
      throw ArgumentError(
        'Together messages are limited to ${TogetherMessage.maxTextLength} characters.',
      );
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
    await _peer?.send('chat', payload: {'text': text});
  }

  Future<void> sendMoment(
    Duration position, {
    String text = 'Look at this moment',
  }) async {
    final session = state.session;
    final sender = _localParticipantId;
    if (session == null || sender == null) return;
    final clean = text.trim().isEmpty ? 'Look at this moment' : text.trim();
    final now = DateTime.now().toUtc();
    _room.receiveMessage(
      TogetherMessage(
        id: _ephemeralId('moment'),
        sessionId: session.id,
        senderParticipantId: sender,
        text: clean,
        kind: TogetherMessageKind.moment,
        mediaPosition: position,
        createdAt: now,
      ),
      conversationVisible: true,
    );
    notifyListeners();
    await _peer?.send('moment', payload: {
      'text': clean,
      'position_ms': position.inMilliseconds,
    });
  }

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
    await _peer?.send('reaction', payload: {'reaction': reaction});
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
    await _packetSub?.cancel();
    await _peerStateSub?.cancel();
    await _errorSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    _packetSub = null;
    _peerStateSub = null;
    _errorSub = null;
    _playingSub = null;
    _completedSub = null;

    final mediaHost = _mediaHost;
    final mediaGuest = _mediaGuest;
    final peer = _peer;
    _mediaHost = null;
    _mediaGuest = null;
    _peer = null;
    await mediaHost?.stop();
    await mediaGuest?.stop();
    await peer?.dispose();

    _invite = null;
    _guestPlan = null;
    _descriptor = null;
    _adapter = null;
    _localParticipantId = null;
    _descriptorCompleter = null;
    if (_room.state.session != null) {
      _room.close(DateTime.now().toUtc());
      _room.clearClosedRoom();
    }
    if (notify) notifyListeners();
  }

  void _attachPeer(AnywhereTogetherPeer peer) {
    _packetSub = peer.packets.listen(_handlePacket);
    _peerStateSub = peer.states.listen(_handlePeerState);
    _errorSub = peer.errors.listen((error) {
      _lastError = error;
      notifyListeners();
    });
  }

  Future<void> _connectHost(AnywhereTogetherPeer peer) async {
    try {
      await peer.connect();
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> _waitUntilConnected(AnywhereTogetherPeer peer) async {
    if (peer.isConnected) return;
    await peer.states
        .firstWhere(
          (value) =>
              value == AnywhereTogetherPeerState.connected ||
              value == AnywhereTogetherPeerState.failed ||
              value == AnywhereTogetherPeerState.closed,
        )
        .timeout(const Duration(seconds: 35))
        .then((value) {
      if (value != AnywhereTogetherPeerState.connected) {
        throw StateError('Anywhere Together could not establish a peer path.');
      }
    });
  }

  Future<AnywhereMediaDescriptor> _waitForDescriptor() async {
    final existing = _descriptor;
    if (existing != null) return existing;
    final completer = _descriptorCompleter ??= Completer<AnywhereMediaDescriptor>();
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'The host did not provide Together media information.',
      ),
    );
  }

  void _handlePeerState(AnywhereTogetherPeerState peerState) {
    final session = state.session;
    final now = DateTime.now().toUtc();

    if (peerState == AnywhereTogetherPeerState.connected) {
      if (isHost) {
        final descriptor = _descriptor;
        if (descriptor != null) {
          unawaited(_peer?.send('media', payload: descriptor.toJson()));
        }
      }
      if (session != null && session.isActive) {
        _setRemoteParticipantConnected(true, now);
        try {
          _room.connected(TogetherConnectionPath.internet, now);
        } catch (_) {}
      }
    } else if (peerState == AnywhereTogetherPeerState.reconnecting ||
        peerState == AnywhereTogetherPeerState.failed) {
      if (session != null && session.isActive) {
        _setRemoteParticipantConnected(false, now);
        try {
          _room.reconnecting(now);
        } catch (_) {}
      }
    } else if (peerState == AnywhereTogetherPeerState.closed) {
      _setRemoteParticipantConnected(false, now);
    }
    notifyListeners();
  }

  void _handlePacket(AnywhereTogetherPacket packet) {
    final peerRole = role;
    final session = state.session;

    if (packet.type == 'media') {
      final descriptor = AnywhereMediaDescriptor.tryParse(packet.payload);
      if (descriptor != null) {
        _descriptor = descriptor;
        final completer = _descriptorCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(descriptor);
        }
      }
      return;
    }

    if (packet.type == 'ping' && peerRole == AnywhereTogetherRole.host) {
      final guestSendUs = packet.payload['guest_send_us'];
      final adapter = _adapter;
      if (guestSendUs is int && adapter != null) {
        unawaited(_peer?.send('pong', payload: {
          'guest_send_us': guestSendUs,
          'host_reply_us': adapter.monotonicClock.elapsedMicroseconds,
        }));
      }
      return;
    }

    if (session == null || !session.isActive) return;
    final remoteId = _remoteParticipantId(session);
    if (remoteId == null) return;

    switch (packet.type) {
      case 'playback':
        if (peerRole != AnywhereTogetherRole.guest) return;
        final remote = TogetherPlaybackState.tryParse(packet.payload);
        final adapter = _adapter;
        if (remote != null && adapter != null) {
          unawaited(adapter.applyRemoteState(remote));
        }
        return;
      case 'pong':
        if (peerRole != AnywhereTogetherRole.guest) return;
        final guestSendUs = packet.payload['guest_send_us'];
        final hostReplyUs = packet.payload['host_reply_us'];
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
        return;
      case 'chat':
        _receivePeerText(packet, remoteId, TogetherMessageKind.text);
        return;
      case 'moment':
        _receivePeerMoment(packet, remoteId);
        return;
      case 'reaction':
        _receivePeerReaction(packet, remoteId);
        return;
      case 'hello':
      case 'bye':
      case 'media':
      case 'ping':
        return;
    }
  }

  Future<void> _sendHostState() async {
    final peer = _peer;
    final adapter = _adapter;
    final session = state.session;
    if (peer == null ||
        !peer.isConnected ||
        adapter == null ||
        session == null ||
        !session.isActive ||
        !isHost) {
      return;
    }
    try {
      await peer.send(
        'playback',
        payload: adapter.captureHostState(
          mediaRevision: session.mediaRevision,
        ).toJson(),
      );
    } catch (_) {}
  }

  Future<void> _sendClockPing() async {
    final peer = _peer;
    final adapter = _adapter;
    if (peer == null || !peer.isConnected || adapter == null || !isGuest) {
      return;
    }
    try {
      await peer.send('ping', payload: {
        'guest_send_us': adapter.monotonicClock.elapsedMicroseconds,
      });
    } catch (_) {}
  }

  void _bindHostPlayer(Player player, {bool replaceAdapter = true}) {
    if (replaceAdapter) {
      final session = state.session;
      _adapter = MediaKitTogetherAdapter(player: player);
      if (session != null) {
        _adapter!.resetForMediaRevision(session.mediaRevision);
      }
    }
    unawaited(_playingSub?.cancel());
    unawaited(_completedSub?.cancel());
    _playingSub = player.stream.playing.listen(
      (_) => unawaited(_sendHostState()),
    );
    _completedSub = player.stream.completed.listen((completed) {
      if (!completed || !state.hasActiveSession) return;
      try {
        _room.playbackEnded(DateTime.now().toUtc());
        notifyListeners();
        unawaited(_sendHostState());
      } catch (_) {}
    });
  }

  Future<bool> _matchesLocalCandidate(
    MediaItem? candidate,
    AnywhereMediaDescriptor remote,
  ) async {
    if (candidate == null || candidate.fileSizeBytes != remote.byteLength) {
      return false;
    }
    try {
      final local = await MediaFingerprintService.instance.identify(
        filePath: candidate.filePath,
        duration: candidate.duration,
        mimeType: _mimeType(candidate.fileName),
      );
      return local.byteLength == remote.byteLength &&
          local.fingerprint == remote.fingerprint;
    } catch (_) {
      return false;
    }
  }

  void _receivePeerText(
    AnywhereTogetherPacket packet,
    String senderId,
    TogetherMessageKind kind,
  ) {
    final session = state.session;
    final text = _text(packet.payload['text']);
    if (session == null || text == null || text.length > TogetherMessage.maxTextLength) {
      return;
    }
    _room.receiveMessage(
      TogetherMessage(
        id: packet.id,
        sessionId: session.id,
        senderParticipantId: senderId,
        text: text,
        kind: kind,
        createdAt: DateTime.now().toUtc(),
      ),
      conversationVisible: false,
    );
    notifyListeners();
  }

  void _receivePeerMoment(AnywhereTogetherPacket packet, String senderId) {
    final session = state.session;
    final text = _text(packet.payload['text']) ?? 'Look at this moment';
    final positionMs = packet.payload['position_ms'];
    if (session == null || positionMs is! int || positionMs < 0) return;
    _room.receiveMessage(
      TogetherMessage(
        id: packet.id,
        sessionId: session.id,
        senderParticipantId: senderId,
        text: text,
        kind: TogetherMessageKind.moment,
        mediaPosition: Duration(milliseconds: positionMs),
        createdAt: DateTime.now().toUtc(),
      ),
      conversationVisible: false,
    );
    notifyListeners();
  }

  void _receivePeerReaction(AnywhereTogetherPacket packet, String senderId) {
    final session = state.session;
    final reaction = _text(packet.payload['reaction']);
    if (session == null ||
        reaction == null ||
        !supportedReactions.contains(reaction)) {
      return;
    }
    _room.receiveMessage(
      TogetherMessage(
        id: packet.id,
        sessionId: session.id,
        senderParticipantId: senderId,
        text: reaction,
        kind: TogetherMessageKind.reaction,
        createdAt: DateTime.now().toUtc(),
      ),
      conversationVisible: false,
    );
    notifyListeners();
  }

  void _setRemoteParticipantConnected(bool connected, DateTime now) {
    final session = state.session;
    if (session == null || !session.isActive) return;
    final localId = _localParticipantId;
    final remote = session.participants
        .where((participant) => participant.id != localId)
        .firstOrNull;
    if (remote == null) return;
    try {
      _room.addParticipant(remote.copyWith(isConnected: connected), now);
    } catch (_) {}
  }

  String? _remoteParticipantId(TogetherSession session) {
    final local = _localParticipantId;
    return session.participants
        .where((participant) => participant.id != local)
        .firstOrNull
        ?.id;
  }

  TogetherParticipant _participant(
    TogetherRoomParticipantView view, {
    required TogetherParticipantRole role,
    required bool connected,
    required DateTime now,
  }) {
    return TogetherParticipant(
      id: _participantId(
        view,
        fallback: role == TogetherParticipantRole.host
            ? 'anywhere-host'
            : 'anywhere-guest',
      ),
      displayName: _displayName(view),
      username: view.username.isEmpty ? null : view.username,
      role: role,
      isConnected: connected,
      joinedAt: now,
    );
  }

  static String _participantId(
    TogetherRoomParticipantView view, {
    required String fallback,
  }) {
    final id = view.otyaId.trim();
    return id.isEmpty ? fallback : id;
  }

  static String _displayName(TogetherRoomParticipantView view) {
    final display = view.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    if (view.username.isNotEmpty) return '@${view.username}';
    return 'Otya user';
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  String _ephemeralId(String prefix) {
    final suffix = List<int>.generate(8, (_) => _random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

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

  static String _friendlyError(Object error) {
    if (error is TimeoutException) return error.message ?? 'Together timed out.';
    if (error is StateError) return error.message;
    return 'Anywhere Together could not start right now.';
  }

  static String? _mimeType(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.mp4')) return 'video/mp4';
    if (name.endsWith('.mkv')) return 'video/x-matroska';
    if (name.endsWith('.webm')) return 'video/webm';
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (name.endsWith('.m4v')) return 'video/x-m4v';
    if (name.endsWith('.mp3')) return 'audio/mpeg';
    if (name.endsWith('.m4a')) return 'audio/mp4';
    if (name.endsWith('.aac')) return 'audio/aac';
    if (name.endsWith('.flac')) return 'audio/flac';
    if (name.endsWith('.ogg')) return 'audio/ogg';
    if (name.endsWith('.wav')) return 'audio/wav';
    return null;
  }
}
