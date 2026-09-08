import 'dart:async';
import 'dart:io';

import 'anywhere_together_media_bridge.dart';
import 'anywhere_together_peer.dart';
import 'anywhere_together_protocol.dart';
import 'together_control_client.dart';

class AnywhereTogetherGroupPacket {
  final String participantId;
  final TogetherRoomParticipantView participant;
  final AnywhereTogetherPeer peer;
  final AnywhereTogetherPacket packet;

  const AnywhereTogetherGroupPacket({
    required this.participantId,
    required this.participant,
    required this.peer,
    required this.packet,
  });
}

class AnywhereTogetherGroupPeerState {
  final String participantId;
  final TogetherRoomParticipantView participant;
  final AnywhereTogetherPeer peer;
  final AnywhereTogetherPeerState state;

  const AnywhereTogetherGroupPeerState({
    required this.participantId,
    required this.participant,
    required this.peer,
    required this.state,
  });
}

class AnywhereTogetherGroupPeerError {
  final String participantId;
  final TogetherRoomParticipantView participant;
  final String message;

  const AnywhereTogetherGroupPeerError({
    required this.participantId,
    required this.participant,
    required this.message,
  });
}

class _AnywhereTogetherGroupEntry {
  final String participantId;
  final TogetherRoomCreation creation;
  final AnywhereTogetherPeer peer;
  final AnywhereTogetherMediaHost? mediaHost;
  final StreamSubscription<AnywhereTogetherPacket> packetSub;
  final StreamSubscription<AnywhereTogetherPeerState> stateSub;
  final StreamSubscription<String> errorSub;

  const _AnywhereTogetherGroupEntry({
    required this.participantId,
    required this.creation,
    required this.peer,
    required this.packetSub,
    required this.stateSub,
    required this.errorSub,
    this.mediaHost,
  });
}

/// Host-side fan-out for a small Anywhere Together room.
///
/// A group is deliberately composed from the same private one-to-one WebRTC
/// connection already used by OTYA. The backend remains a short-lived control
/// plane; playback/chat packets and optional requested media bytes stay on the
/// encrypted phone-to-phone data channels.
class AnywhereTogetherGroupHost {
  AnywhereTogetherGroupHost({TogetherControlClient? controlClient})
      : controlClient = controlClient ?? TogetherControlClient.instance;

  static const int maxGuests = 3;

  final TogetherControlClient controlClient;
  final Map<String, _AnywhereTogetherGroupEntry> _entries = {};

  final StreamController<AnywhereTogetherGroupPacket> _packets =
      StreamController<AnywhereTogetherGroupPacket>.broadcast();
  final StreamController<AnywhereTogetherGroupPeerState> _states =
      StreamController<AnywhereTogetherGroupPeerState>.broadcast();
  final StreamController<AnywhereTogetherGroupPeerError> _errors =
      StreamController<AnywhereTogetherGroupPeerError>.broadcast();

  bool _closed = false;

  Stream<AnywhereTogetherGroupPacket> get packets => _packets.stream;
  Stream<AnywhereTogetherGroupPeerState> get states => _states.stream;
  Stream<AnywhereTogetherGroupPeerError> get errors => _errors.stream;

  int get guestCount => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  Iterable<String> get participantIds => _entries.keys;

  Iterable<TogetherRoomParticipantView> get participants =>
      _entries.values.map((entry) => entry.creation.room.guest);

  Iterable<AnywhereTogetherPeer> get peers =>
      _entries.values.map((entry) => entry.peer);

  Future<void> addGuest({
    required TogetherRoomCreation creation,
    required File mediaFile,
    required bool allowMediaFallback,
  }) async {
    if (_closed) throw StateError('Together group host is closed.');
    if (_entries.length >= maxGuests) {
      throw StateError('Together supports up to $maxGuests invited friends.');
    }

    final participantId = _participantId(creation.room.guest);
    if (_entries.containsKey(participantId)) {
      throw StateError('That friend is already in this Together group.');
    }

    final peer = AnywhereTogetherPeer(
      roomId: creation.room.roomId,
      role: AnywhereTogetherRole.host,
    );
    AnywhereTogetherMediaHost? mediaHost;
    if (allowMediaFallback) {
      mediaHost = AnywhereTogetherMediaHost(peer: peer);
      await mediaHost.start(mediaFile);
    }

    final packetSub = _listenPackets(
      participantId: participantId,
      participant: creation.room.guest,
      peer: peer,
    );
    final stateSub = _listenStates(
      participantId: participantId,
      participant: creation.room.guest,
      peer: peer,
    );
    final errorSub = _listenErrors(
      participantId: participantId,
      participant: creation.room.guest,
      peer: peer,
    );

    _entries[participantId] = _AnywhereTogetherGroupEntry(
      participantId: participantId,
      creation: creation,
      peer: peer,
      mediaHost: mediaHost,
      packetSub: packetSub,
      stateSub: stateSub,
      errorSub: errorSub,
    );
  }

  StreamSubscription<AnywhereTogetherPacket> _listenPackets({
    required String participantId,
    required TogetherRoomParticipantView participant,
    required AnywhereTogetherPeer peer,
  }) {
    return peer.packets.listen((packet) {
      if (_closed) return;
      _packets.add(
        AnywhereTogetherGroupPacket(
          participantId: participantId,
          participant: participant,
          peer: peer,
          packet: packet,
        ),
      );
    });
  }

  StreamSubscription<AnywhereTogetherPeerState> _listenStates({
    required String participantId,
    required TogetherRoomParticipantView participant,
    required AnywhereTogetherPeer peer,
  }) {
    return peer.states.listen((state) {
      if (_closed) return;
      _states.add(
        AnywhereTogetherGroupPeerState(
          participantId: participantId,
          participant: participant,
          peer: peer,
          state: state,
        ),
      );
    });
  }

  StreamSubscription<String> _listenErrors({
    required String participantId,
    required TogetherRoomParticipantView participant,
    required AnywhereTogetherPeer peer,
  }) {
    return peer.errors.listen((message) {
      if (_closed) return;
      _errors.add(
        AnywhereTogetherGroupPeerError(
          participantId: participantId,
          participant: participant,
          message: message,
        ),
      );
    });
  }

  Future<void> connectParticipant(String participantId) async {
    final entry = _entries[participantId];
    if (entry == null || _closed) return;
    await entry.peer.connect();
  }

  void connectAll() {
    for (final entry in _entries.values) {
      unawaited(_connectQuietly(entry));
    }
  }

  Future<void> sendTo(
    String participantId,
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    final entry = _entries[participantId];
    if (entry == null || !entry.peer.isConnected || _closed) return;
    await entry.peer.send(type, payload: payload);
  }

  Future<void> broadcast(
    String type, {
    Map<String, dynamic> payload = const {},
    String? exceptParticipantId,
  }) async {
    final futures = <Future<void>>[];
    for (final entry in _entries.values) {
      if (entry.participantId == exceptParticipantId ||
          !entry.peer.isConnected) {
        continue;
      }
      futures.add(
        entry.peer.send(type, payload: payload).catchError((_) {}),
      );
    }
    if (futures.isNotEmpty) await Future.wait(futures);
  }

  bool isConnected(String participantId) =>
      _entries[participantId]?.peer.isConnected == true;

  int get connectedGuestCount =>
      _entries.values.where((entry) => entry.peer.isConnected).length;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final entries = _entries.values.toList(growable: false);
    _entries.clear();

    for (final entry in entries) {
      await entry.packetSub.cancel();
      await entry.stateSub.cancel();
      await entry.errorSub.cancel();
      await entry.mediaHost?.stop();
      await entry.peer.dispose();
      try {
        await controlClient.closeRoom(entry.creation.room.roomId);
      } catch (_) {}
    }

    await _packets.close();
    await _states.close();
    await _errors.close();
  }

  Future<void> _connectQuietly(_AnywhereTogetherGroupEntry entry) async {
    try {
      await entry.peer.connect();
    } catch (error) {
      if (_closed) return;
      _errors.add(
        AnywhereTogetherGroupPeerError(
          participantId: entry.participantId,
          participant: entry.creation.room.guest,
          message: error.toString(),
        ),
      );
    }
  }

  static String _participantId(TogetherRoomParticipantView participant) {
    final publicId = participant.otyaId.trim();
    if (publicId.isNotEmpty) return publicId;
    final username = participant.username.trim().toLowerCase();
    if (username.isNotEmpty) return 'user:$username';
    throw StateError('Together guest identity is incomplete.');
  }
}
