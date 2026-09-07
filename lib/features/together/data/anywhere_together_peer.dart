import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'anywhere_together_protocol.dart';
import 'together_control_client.dart';
import 'together_ice_config_client.dart';

enum AnywhereTogetherRole { host, guest }

enum AnywhereTogetherPeerState {
  idle,
  waitingForPeer,
  connecting,
  connected,
  reconnecting,
  failed,
  closed,
}

/// One private WebRTC peer connection for Anywhere Together.
///
/// The OTYA server is used only for room membership, short-lived ICE config,
/// and offer/answer/ICE setup messages. Once connected, normal Together events
/// use one ordered control data channel while movie byte ranges use a second
/// ordered binary channel. Neither payload is stored by OTYA's backend.
///
/// This transport never captures microphone/camera tracks. OTYA uses WebRTC's
/// encrypted data channels only; normal local playback remains independent.
class AnywhereTogetherPeer {
  AnywhereTogetherPeer({
    required this.roomId,
    required this.role,
    TogetherControlClient? controlClient,
    TogetherIceConfigClient? iceConfigClient,
    this.pollInterval = const Duration(milliseconds: 700),
    this.guestWaitTimeout = const Duration(minutes: 2),
  })  : controlClient = controlClient ?? TogetherControlClient.instance,
        iceConfigClient = iceConfigClient ?? TogetherIceConfigClient.instance;

  static const String controlChannelLabel = 'otya-together-v1';
  static const String mediaChannelLabel = 'otya-together-media-v1';
  static const int _maxSeenPacketIds = 256;
  static const int _mediaHighWaterBytes = 2 * 1024 * 1024;

  final String roomId;
  final AnywhereTogetherRole role;
  final TogetherControlClient controlClient;
  final TogetherIceConfigClient iceConfigClient;
  final Duration pollInterval;
  final Duration guestWaitTimeout;

  final StreamController<AnywhereTogetherPacket> _packets =
      StreamController<AnywhereTogetherPacket>.broadcast();
  final StreamController<AnywhereTogetherPeerState> _states =
      StreamController<AnywhereTogetherPeerState>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final StreamController<RTCDataChannelMessage> _mediaMessages =
      StreamController<RTCDataChannelMessage>.broadcast();
  final LinkedHashSet<String> _seenPacketIds = LinkedHashSet<String>();
  final List<RTCIceCandidate> _queuedRemoteCandidates = [];

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _controlDataChannel;
  RTCDataChannel? _mediaDataChannel;
  Timer? _pollTimer;
  Timer? _disconnectTimer;
  AnywhereTogetherPeerState _state = AnywhereTogetherPeerState.idle;
  String? _lastSignalId;
  bool _polling = false;
  bool _hasRemoteDescription = false;
  bool _closing = false;
  int _packetSequence = 0;

  Stream<AnywhereTogetherPacket> get packets => _packets.stream;
  Stream<AnywhereTogetherPeerState> get states => _states.stream;
  Stream<String> get errors => _errors.stream;
  Stream<RTCDataChannelMessage> get mediaMessages => _mediaMessages.stream;
  AnywhereTogetherPeerState get state => _state;
  bool get isConnected => _state == AnywhereTogetherPeerState.connected;
  bool get mediaReady =>
      _mediaDataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> connect() async {
    if (_state != AnywhereTogetherPeerState.idle) {
      throw StateError('Anywhere Together peer has already started.');
    }
    if (roomId.trim().isEmpty) {
      throw ArgumentError.value(roomId, 'roomId');
    }

    try {
      if (role == AnywhereTogetherRole.host) {
        _setState(AnywhereTogetherPeerState.waitingForPeer);
        await _waitForGuest();
      }

      _setState(AnywhereTogetherPeerState.connecting);
      final iceResult = await iceConfigClient.fetchForRoom(roomId);
      final ice = iceResult.value;
      if (!iceResult.ok || ice == null) {
        throw StateError(
          iceResult.error ?? 'Could not prepare Together connection.',
        );
      }

      final peer = await createPeerConnection(
        ice.peerConnectionConfiguration,
      );
      _peerConnection = peer;
      _wirePeerCallbacks(peer);
      _startPolling();

      if (role == AnywhereTogetherRole.host) {
        final controlInit = RTCDataChannelInit()
          ..ordered = true
          ..protocol = controlChannelLabel;
        final controlChannel = await peer.createDataChannel(
          controlChannelLabel,
          controlInit,
        );
        _attachControlDataChannel(controlChannel);

        final mediaInit = RTCDataChannelInit()
          ..ordered = true
          ..protocol = mediaChannelLabel;
        final mediaChannel = await peer.createDataChannel(
          mediaChannelLabel,
          mediaInit,
        );
        _attachMediaDataChannel(mediaChannel);
        await _sendFreshOffer(peer);
      } else {
        await _pollSignals();
      }
    } catch (error) {
      _emitError(_friendlyError(error));
      _setState(AnywhereTogetherPeerState.failed);
      await _releaseNativeResources();
      rethrow;
    }
  }

  Future<void> send(
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    final channel = _controlDataChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Anywhere Together is not connected.');
    }

    final encoded = AnywhereTogetherPacket.encode(
      id: _nextPacketId(),
      type: type,
      payload: payload,
    );
    await channel.send(RTCDataChannelMessage(encoded));
  }

  Future<void> sendMediaText(String value) async {
    await _sendMediaMessage(RTCDataChannelMessage(value));
  }

  Future<void> sendMediaBinary(Uint8List value) async {
    await _sendMediaMessage(RTCDataChannelMessage.fromBinary(value));
  }

  Future<void> _sendMediaMessage(RTCDataChannelMessage message) async {
    final channel = _mediaDataChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Anywhere Together media path is not connected.');
    }
    await _waitForMediaBuffer(channel);
    await channel.send(message);
  }

  Future<void> _waitForMediaBuffer(RTCDataChannel channel) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((channel.bufferedAmount ?? 0) > _mediaHighWaterBytes) {
      if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        throw StateError('Anywhere Together media path closed.');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Anywhere Together media path is congested.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }

  Future<void> close({
    bool notifyPeer = true,
    bool closeRoom = true,
  }) async {
    if (_closing || _state == AnywhereTogetherPeerState.closed) return;
    _closing = true;

    if (notifyPeer) {
      try {
        await send('bye');
      } catch (_) {}
      try {
        await controlClient.sendSignal(roomId: roomId, type: 'bye');
      } catch (_) {}
    }

    _setState(AnywhereTogetherPeerState.closed);
    await _releaseNativeResources();
    if (closeRoom) {
      try {
        await controlClient.closeRoom(roomId);
      } catch (_) {}
    }
    _closing = false;
  }

  Future<void> dispose() async {
    await close(notifyPeer: false, closeRoom: false);
    if (!_packets.isClosed) await _packets.close();
    if (!_states.isClosed) await _states.close();
    if (!_errors.isClosed) await _errors.close();
    if (!_mediaMessages.isClosed) await _mediaMessages.close();
  }

  Future<void> _waitForGuest() async {
    final deadline = DateTime.now().add(guestWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await controlClient.getRoom(roomId);
      if (result.value?.guest.connected == true) return;
      if (result.code == 'ROOM_NOT_FOUND') {
        throw StateError(result.error ?? 'Together room is unavailable.');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException(
      'The invited person did not join Together in time.',
    );
  }

  void _wirePeerCallbacks(RTCPeerConnection peer) {
    peer.onIceCandidate = (candidate) {
      unawaited(_sendIceCandidate(candidate));
    };
    peer.onDataChannel = (channel) {
      if (role != AnywhereTogetherRole.guest) return;
      if (channel.label == controlChannelLabel) {
        _attachControlDataChannel(channel);
      } else if (channel.label == mediaChannelLabel) {
        _attachMediaDataChannel(channel);
      }
    };
    peer.onConnectionState = _handleConnectionState;
    peer.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _emitError(
          'Anywhere Together could not find a working network path.',
        );
      }
    };
  }

  void _attachControlDataChannel(RTCDataChannel channel) {
    _controlDataChannel = channel;
    channel.onMessage = (message) {
      if (message.isBinary) return;
      _acceptPacket(message.text);
    };
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _disconnectTimer?.cancel();
        _setState(AnywhereTogetherPeerState.connected);
        _stopPolling();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed &&
          !_closing) {
        _setState(AnywhereTogetherPeerState.reconnecting);
        _startPolling();
      }
    };
  }

  void _attachMediaDataChannel(RTCDataChannel channel) {
    _mediaDataChannel = channel;
    channel.onMessage = (message) {
      if (!_mediaMessages.isClosed) _mediaMessages.add(message);
    };
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed && !_closing) {
        _emitError('Anywhere Together media path closed.');
      }
    };
  }

  void _acceptPacket(String raw) {
    final packet = AnywhereTogetherPacket.decode(raw);
    if (packet == null) return;
    if (!_seenPacketIds.add(packet.id)) return;
    if (_seenPacketIds.length > _maxSeenPacketIds) {
      _seenPacketIds.remove(_seenPacketIds.first);
    }

    if (packet.type == 'bye') {
      unawaited(close(notifyPeer: false, closeRoom: false));
      return;
    }
    if (!_packets.isClosed) _packets.add(packet);
  }

  void _handleConnectionState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimer?.cancel();
        if (_controlDataChannel?.state ==
            RTCDataChannelState.RTCDataChannelOpen) {
          _setState(AnywhereTogetherPeerState.connected);
          _stopPolling();
        }
        return;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (_closing) return;
        _setState(AnywhereTogetherPeerState.reconnecting);
        _startPolling();
        _disconnectTimer?.cancel();
        _disconnectTimer = Timer(const Duration(seconds: 3), () {
          unawaited(_attemptRecovery());
        });
        return;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (_closing) return;
        _setState(AnywhereTogetherPeerState.failed);
        _emitError('Anywhere Together connection failed.');
        return;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (!_closing) _setState(AnywhereTogetherPeerState.closed);
        return;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        if (_state != AnywhereTogetherPeerState.reconnecting) {
          _setState(AnywhereTogetherPeerState.connecting);
        }
        return;
    }
  }

  Future<void> _attemptRecovery() async {
    if (_closing ||
        _state != AnywhereTogetherPeerState.reconnecting ||
        _peerConnection == null) {
      return;
    }

    try {
      if (role == AnywhereTogetherRole.host) {
        await _peerConnection!.restartIce();
        await _sendFreshOffer(_peerConnection!);
      }
    } catch (error) {
      _emitError(_friendlyError(error));
    }
  }

  Future<void> _sendFreshOffer(RTCPeerConnection peer) async {
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    final result = await controlClient.sendSignal(
      roomId: roomId,
      type: 'offer',
      payload: {
        'sdp': offer.sdp,
        'description_type': offer.type,
      },
    );
    if (!result.ok) {
      throw StateError(result.error ?? 'Could not send Together offer.');
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    final raw = candidate.candidate;
    if (_closing || raw == null || raw.trim().isEmpty) return;

    final result = await controlClient.sendSignal(
      roomId: roomId,
      type: 'ice',
      payload: {
        'candidate': raw,
        'sdp_mid': candidate.sdpMid,
        'sdp_mline_index': candidate.sdpMLineIndex,
      },
    );
    if (!result.ok && result.code != 'GUEST_NOT_JOINED') {
      _emitError(
        result.error ?? 'Could not send Together network candidate.',
      );
    }
  }

  void _startPolling() {
    if (_closing || _pollTimer != null) return;
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(_pollSignals());
    });
    unawaited(_pollSignals());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollSignals() async {
    if (_closing || _polling) return;
    _polling = true;
    try {
      final result = await controlClient.pollSignals(
        roomId: roomId,
        after: _lastSignalId,
      );
      if (!result.ok) {
        if (result.code == 'ROOM_NOT_FOUND') {
          await close(notifyPeer: false, closeRoom: false);
        }
        return;
      }

      for (final signal in result.value ?? const <TogetherSignal>[]) {
        _lastSignalId = signal.id;
        if (!_isExpectedSender(signal.senderRole)) continue;
        await _acceptSignal(signal);
      }
    } catch (error) {
      _emitError(_friendlyError(error));
    } finally {
      _polling = false;
    }
  }

  bool _isExpectedSender(String senderRole) {
    return switch (role) {
      AnywhereTogetherRole.host => senderRole == 'guest',
      AnywhereTogetherRole.guest => senderRole == 'host',
    };
  }

  Future<void> _acceptSignal(TogetherSignal signal) async {
    final peer = _peerConnection;
    if (peer == null) return;

    switch (signal.type) {
      case 'offer':
        if (role != AnywhereTogetherRole.guest) return;
        final payload = _signalPayload(signal.payload);
        final sdp = payload?['sdp'];
        if (sdp is! String || sdp.isEmpty) return;
        await peer.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        _hasRemoteDescription = true;
        await _flushRemoteCandidates(peer);
        final answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);
        final result = await controlClient.sendSignal(
          roomId: roomId,
          type: 'answer',
          payload: {
            'sdp': answer.sdp,
            'description_type': answer.type,
          },
        );
        if (!result.ok) {
          throw StateError(
            result.error ?? 'Could not answer Together connection.',
          );
        }
        return;
      case 'answer':
        if (role != AnywhereTogetherRole.host) return;
        final payload = _signalPayload(signal.payload);
        final sdp = payload?['sdp'];
        if (sdp is! String || sdp.isEmpty) return;
        await peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        _hasRemoteDescription = true;
        await _flushRemoteCandidates(peer);
        return;
      case 'ice':
        final payload = _signalPayload(signal.payload);
        final raw = payload?['candidate'];
        if (raw is! String || raw.isEmpty) return;
        final mid = payload?['sdp_mid'];
        final line = payload?['sdp_mline_index'];
        final candidate = RTCIceCandidate(
          raw,
          mid is String ? mid : null,
          line is int ? line : null,
        );
        if (_hasRemoteDescription) {
          await peer.addCandidate(candidate);
        } else {
          _queuedRemoteCandidates.add(candidate);
        }
        return;
      case 'bye':
        await close(notifyPeer: false, closeRoom: false);
        return;
    }
  }

  Future<void> _flushRemoteCandidates(RTCPeerConnection peer) async {
    if (!_hasRemoteDescription || _queuedRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_queuedRemoteCandidates);
    _queuedRemoteCandidates.clear();
    for (final candidate in pending) {
      await peer.addCandidate(candidate);
    }
  }

  Future<void> _releaseNativeResources() async {
    _stopPolling();
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _queuedRemoteCandidates.clear();
    _hasRemoteDescription = false;

    final controlChannel = _controlDataChannel;
    _controlDataChannel = null;
    try {
      await controlChannel?.close();
    } catch (_) {}

    final mediaChannel = _mediaDataChannel;
    _mediaDataChannel = null;
    try {
      await mediaChannel?.close();
    } catch (_) {}

    final peer = _peerConnection;
    _peerConnection = null;
    try {
      await peer?.close();
    } catch (_) {}
    try {
      await peer?.dispose();
    } catch (_) {}
  }

  void _setState(AnywhereTogetherPeerState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _emitError(String message) {
    final clean = message.trim();
    if (clean.isEmpty || _errors.isClosed) return;
    _errors.add(clean);
  }

  String _nextPacketId() {
    _packetSequence++;
    return '${DateTime.now().microsecondsSinceEpoch}-${_packetSequence.toRadixString(36)}';
  }

  static Map<String, dynamic>? _signalPayload(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return error.message ?? 'Together timed out.';
    }
    if (error is StateError) return error.message;
    return 'Anywhere Together could not connect right now.';
  }
}
