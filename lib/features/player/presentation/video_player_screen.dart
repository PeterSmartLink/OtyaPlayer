import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/database/otya_database.dart';
import '../../../core/models/media_item.dart';
import '../../../core/services/auth_provider.dart';
import '../../../core/services/ffmpeg_service.dart';
import '../../../core/services/media_kit_engine.dart';
import '../../../core/services/native_share_service.dart';
import '../../../core/services/pip_service.dart';
import '../../../core/services/playback_coordinator.dart';
import '../../../features/settings/settings_provider.dart';
import '../../../shared/widgets/speed_picker_sheet.dart';
import '../../together/application/anywhere_together_runtime.dart';
import '../../together/application/nearby_together_runtime.dart';
import '../../together/application/nearby_together_session.dart';
import '../../together/data/anywhere_together_security.dart';
import '../../together/presentation/anywhere_together_live_surface.dart';
import '../../together/presentation/anywhere_together_sheet.dart';
import '../../together/presentation/nearby_together_host_sheet.dart';
import '../../together/presentation/nearby_together_join_sheet.dart';
import '../../together/presentation/nearby_together_live_surface.dart';
import '../../together/presentation/together_ambient_overlay.dart';
import '../../together/presentation/together_entry_sheet.dart';
import '../../transfer/data/transfer_security_policy.dart';
import 'queue_screen.dart';
import 'widgets/video_gesture_layer.dart';
import 'widgets/video_player_overlays.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem mediaItem;

  const VideoPlayerScreen({super.key, required this.mediaItem});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver {
  bool _pipSupported = false;
  bool _pipAutoEnabled = false;
  bool _pipInitialized = false;
  bool _handoffToAnotherVideo = false;
  bool _togetherGuestStreamActive = false;
  bool _anywhereTogetherActive = false;
  Duration? _positionBeforeTogetherStream;
  late final Duration _savedPosition;

  bool _controlsVisible = true;
  bool _isLocked = false;
  bool _isMuted = false;
  bool _ccEnabled = false;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  int _aspectRatioIndex = 0;
  bool _isPlaying = true;
  bool _isSeeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Player? _player;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;

  static const _aspectRatioLabels = [
    'Fit to Screen',
    'Center Crop',
    'Stretch',
  ];
  static const _aspectRatioFits = [
    BoxFit.contain,
    BoxFit.cover,
    BoxFit.fill,
  ];

  String get _visibleTitle =>
      _togetherGuestStreamActive ? 'Together video' : widget.mediaItem.title;

  bool get _persistLocalPosition => !_togetherGuestStreamActive;

  String get _togetherStreamSourceLabel =>
      AnywhereTogetherRuntime.instance.guestStreaming
          ? 'Anywhere Together'
          : 'Nearby Together';

  int? get _togetherStreamByteLength {
    final anywhere = AnywhereTogetherRuntime.instance;
    if (anywhere.guestStreaming) {
      return anywhere.guestPlan?.remoteMedia.byteLength;
    }
    return NearbyTogetherRuntime.instance.guestPlan?.remoteMedia.byteLength;
  }

  @override
  void initState() {
    super.initState();
    _savedPosition =
        OtyaDatabase.instance.getSeekPosition(widget.mediaItem.id) ??
            Duration.zero;
    _position = _savedPosition;
    WidgetsBinding.instance.addObserver(this);
    NearbyTogetherRuntime.instance.addListener(_handleTogetherRuntimeChanged);
    AnywhereTogetherRuntime.instance.addListener(
      _handleAnywhereTogetherRuntimeChanged,
    );
    _initOrientationFromVideo();
    _initPip();
    _resetHideTimer();
  }

  void _handleTogetherRuntimeChanged() {
    final runtime = NearbyTogetherRuntime.instance;
    if (!mounted || !runtime.guestStreaming || _togetherGuestStreamActive) {
      return;
    }
    setState(() {
      _togetherGuestStreamActive = true;
      _ccEnabled = false;
      _position = Duration.zero;
      _duration = runtime.guestPlan?.remoteMedia.duration ?? Duration.zero;
    });
  }

  void _handleAnywhereTogetherRuntimeChanged() {
    final runtime = AnywhereTogetherRuntime.instance;
    if (!mounted) return;
    final activeChanged = _anywhereTogetherActive != runtime.active;
    final startsStream = runtime.guestStreaming && !_togetherGuestStreamActive;
    if (!activeChanged && !startsStream) return;
    setState(() {
      _anywhereTogetherActive = runtime.active;
      if (startsStream) {
        _togetherGuestStreamActive = true;
        _ccEnabled = false;
        _position = Duration.zero;
        _duration = Duration(
          milliseconds: runtime.guestPlan?.remoteMedia.durationMs ?? 0,
        );
      }
    });
  }

  Future<void> _initPip() async {
    _pipSupported = await PipService.instance.isPipSupported();
    _pipAutoEnabled = ref.read(settingsProvider).autoPip;
    await PipService.instance.setVideoPlaying(playing: _isPlaying);
    _pipInitialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _persistLocalPosition &&
        _position > Duration.zero) {
      OtyaDatabase.instance.saveSeekPosition(widget.mediaItem.id, _position);
    }
    if (!_pipInitialized) return;
    if (state == AppLifecycleState.paused &&
        _pipAutoEnabled &&
        _pipSupported &&
        _isPlaying) {
      PipService.instance.enterPip();
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isLocked) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControlsVisibility() {
    _hideTimer?.cancel();
    if (!mounted || _isLocked) return;
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
      return;
    }
    _resetHideTimer();
  }

  Future<void> _initOrientationFromVideo() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _lockToLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _lockToPortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _toggleOrientation() async {
    HapticFeedback.selectionClick();
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (landscape) {
      await _lockToPortrait();
    } else {
      await _lockToLandscape();
    }
  }

  Future<void> _restoreOrientation() async {
    await PipService.instance.setVideoPlaying(playing: false);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<bool> _openQueuedVideo(MediaItem item) async {
    final nearby = NearbyTogetherRuntime.instance;
    final anywhere = AnywhereTogetherRuntime.instance;
    if ((nearby.active && nearby.isGuest) ||
        (anywhere.active && anywhere.isGuest)) {
      _showHostControlsQueueMessage();
      return false;
    }

    if (anywhere.active) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Finish the current Anywhere Together video before changing the shared video.',
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
      return false;
    }

    if (_persistLocalPosition && _position > Duration.zero) {
      OtyaDatabase.instance.saveSeekPosition(widget.mediaItem.id, _position);
    }

    if (nearby.active && nearby.isHost) {
      try {
        await nearby.prepareHostNextMedia(item);
      } catch (_) {
        await _player?.play();
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nearby.lastError ??
                  'Otya could not change the Together video. Try again.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return false;
      }
    }

    if (!mounted) return false;
    _handoffToAnotherVideo = true;
    context.pushReplacement('/player/video', extra: item);
    return true;
  }

  void _showHostControlsQueueMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The host chooses the shared video while Together is active.'),
        backgroundColor: AppColors.surface,
      ),
    );
  }

  String get size {
    final bytes = widget.mediaItem.fileSizeBytes;
    if (bytes == 0) return 'Unknown';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _toggleSubtitles() async {
    final player = _player;
    if (player == null) return;

    HapticFeedback.selectionClick();
    if (_ccEnabled) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      if (mounted) setState(() => _ccEnabled = false);
      return;
    }

    final tracks = player.state.tracks.subtitle;
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No embedded subtitles found'),
            backgroundColor: AppColors.surface,
          ),
        );
      }
      return;
    }

    await player.setSubtitleTrack(tracks.first);
    if (mounted) setState(() => _ccEnabled = true);
  }

  Future<void> _shareMedia() async {
    try {
      await NativeShareService.shareFile(
        path: widget.mediaItem.filePath,
        text: widget.mediaItem.title,
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTYA could not share that file.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showTogetherEntry() async {
    final player = _player;
    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The video is still getting ready. Try again in a moment.'),
          backgroundColor: AppColors.surface,
        ),
      );
      return;
    }

    final nearby = NearbyTogetherRuntime.instance;
    final anywhere = AnywhereTogetherRuntime.instance;
    if (anywhere.active) {
      await _showActiveAnywhereTogetherRoom();
      return;
    }
    if (nearby.active) {
      await _showActiveNearbyTogetherRoom();
      return;
    }

    final choice = await showTogetherEntrySheet(context);
    if (!mounted || choice == null) return;

    switch (choice) {
      case TogetherEntryChoice.nearbyStart:
        await showNearbyTogetherHostSheet(
          context: context,
          mediaItem: widget.mediaItem,
          player: player,
          displayName: ref.read(displayNameProvider),
        );
        return;
      case TogetherEntryChoice.nearbyJoin:
        final plan = await showNearbyTogetherJoinSheet(
          context: context,
          currentMediaItem: widget.mediaItem,
          player: player,
          displayName: ref.read(displayNameProvider),
        );
        if (!mounted || plan == null) return;
        if (plan.kind == NearbyPlaybackSourceKind.hostLanStream) {
          await _switchToTogetherStream(plan);
        } else {
          await _showActiveNearbyTogetherRoom();
        }
        return;
      case TogetherEntryChoice.anywhereStart:
        await showAnywhereTogetherHostSheet(
          context: context,
          mediaItem: widget.mediaItem,
          player: player,
        );
        return;
      case TogetherEntryChoice.anywhereJoin:
        final plan = await showAnywhereTogetherJoinSheet(
          context: context,
          currentMediaItem: widget.mediaItem,
          player: player,
        );
        if (!mounted || plan == null) return;
        if (plan.kind == AnywherePlaybackSourceKind.hostPeerStream) {
          await _switchToAnywhereTogetherStream(plan);
        } else {
          await _showActiveAnywhereTogetherRoom();
        }
        return;
    }
  }

  Future<void> _switchToTogetherStream(NearbyPlaybackPlan plan) async {
    final player = _player;
    final uri = plan.hostMediaUrl;
    final runtime = NearbyTogetherRuntime.instance;
    if (player == null ||
        uri == null ||
        !runtime.isGuest ||
        !isAllowedTransferUri(uri)) {
      await runtime.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTYA blocked an invalid Together media source.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      _positionBeforeTogetherStream = _position;
      await player.pause();
      await player.open(Media(uri.toString()), play: false);
      runtime.attachPlayer(player);
      if (!mounted) return;
      setState(() {
        _togetherGuestStreamActive = true;
        _position = Duration.zero;
        _duration = plan.remoteMedia.duration ?? Duration.zero;
        _ccEnabled = false;
      });
      await player.play();
      await _showActiveTogetherRoom();
    } catch (_) {
      await runtime.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The nearby video stream could not start. Keep both phones on the same network and try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _switchToAnywhereTogetherStream(
    AnywherePlaybackPlan plan,
  ) async {
    final player = _player;
    final uri = plan.hostMediaUrl;
    final runtime = AnywhereTogetherRuntime.instance;
    if (player == null ||
        uri == null ||
        !runtime.isGuest ||
        !isAllowedAnywhereTogetherMediaUri(uri)) {
      await runtime.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTYA blocked an invalid Anywhere Together media source.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      _positionBeforeTogetherStream = _position;
      await player.pause();
      await player.open(Media(uri.toString()), play: false);
      runtime.attachPlayer(player);
      if (!mounted) return;
      setState(() {
        _togetherGuestStreamActive = true;
        _position = Duration.zero;
        _duration = Duration(milliseconds: plan.remoteMedia.durationMs);
        _ccEnabled = false;
      });
      await player.play();
      await _showActiveAnywhereTogetherRoom();
    } catch (_) {
      await runtime.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The private peer video stream could not start. Check the internet connection on both phones and try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showActiveTogetherRoom() async {
    if (AnywhereTogetherRuntime.instance.active) {
      await _showActiveAnywhereTogetherRoom();
      return;
    }
    await _showActiveNearbyTogetherRoom();
  }

  Future<void> _showActiveNearbyTogetherRoom() async {
    final runtime = NearbyTogetherRuntime.instance;
    if (!mounted || !runtime.active) return;

    await showNearbyTogetherLiveRoomSurface(
      context: context,
      runtime: runtime,
      onMomentTap: (position) => _player?.seek(position),
      onInvite: () {
        if (!runtime.isHost || _player == null) return;
        Navigator.of(context).pop();
        unawaited(showNearbyTogetherHostSheet(
          context: context,
          mediaItem: widget.mediaItem,
          player: _player!,
          displayName: ref.read(displayNameProvider),
        ));
      },
      onLeave: () {
        Navigator.of(context).pop();
        unawaited(_leaveTogetherSession());
      },
      onReplay: runtime.isHost
          ? () {
              _player?.seek(Duration.zero);
              _player?.play();
            }
          : null,
      onChooseNext: runtime.isHost
          ? () {
              Navigator.of(context).pop();
              unawaited(_next());
            }
          : null,
    );
  }

  Future<void> _showActiveAnywhereTogetherRoom() async {
    final runtime = AnywhereTogetherRuntime.instance;
    if (!mounted || !runtime.active) return;

    await showAnywhereTogetherLiveRoomSurface(
      context: context,
      runtime: runtime,
      onMomentTap: (position) => _player?.seek(position),
      onInvite: () {
        if (!runtime.isHost || _player == null) return;
        Navigator.of(context).pop();
        unawaited(showAnywhereTogetherHostSheet(
          context: context,
          mediaItem: widget.mediaItem,
          player: _player!,
        ));
      },
      onLeave: () {
        Navigator.of(context).pop();
        unawaited(_leaveTogetherSession());
      },
      onReplay: runtime.isHost
          ? () {
              _player?.seek(Duration.zero);
              _player?.play();
            }
          : null,
    );
  }

  Future<void> _leaveTogetherSession() async {
    final restoreStream = _togetherGuestStreamActive;
    final restorePosition = _positionBeforeTogetherStream ?? _savedPosition;
    final shouldResume = _isPlaying;
    final player = _player;

    await NearbyTogetherRuntime.instance.stop();
    await AnywhereTogetherRuntime.instance.stop();

    if (!restoreStream || player == null || !mounted) return;
    try {
      await player.open(Media(widget.mediaItem.filePath), play: false);
      if (restorePosition > Duration.zero) {
        await player.seek(restorePosition);
      }
      if (shouldResume) await player.play();
      if (!mounted) return;
      setState(() {
        _togetherGuestStreamActive = false;
        _positionBeforeTogetherStream = null;
        _position = restorePosition;
        _duration = widget.mediaItem.duration;
        _ccEnabled = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTYA left Together, but could not restore the local video.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface.withValues(alpha: 0.96),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!_togetherGuestStreamActive)
              ListTile(
                leading: const Icon(
                  Icons.share_rounded,
                  color: AppColors.accent,
                  size: 22,
                ),
                title: const Text(
                  'Share',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareMedia();
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.people_alt_rounded,
                color: AppColors.accent,
                size: 22,
              ),
              title: Text(
                (NearbyTogetherRuntime.instance.active ||
                        AnywhereTogetherRuntime.instance.active)
                    ? 'Together'
                    : 'Watch Together',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                (NearbyTogetherRuntime.instance.active ||
                        AnywhereTogetherRuntime.instance.active)
                    ? 'Open the active session'
                    : 'Watch nearby or privately over the internet',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                  fontSize: 12,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _showTogetherEntry();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.info_outline_rounded,
                color: AppColors.textSecondary,
                size: 22,
              ),
              title: const Text(
                'Details',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text(
                      'Details',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VideoInfoRow(
                          label: 'Title',
                          value: _visibleTitle,
                        ),
                        VideoInfoRow(
                          label: 'Source',
                          value: _togetherGuestStreamActive
                              ? _togetherStreamSourceLabel
                              : widget.mediaItem.filePath,
                        ),
                        VideoInfoRow(
                          label: 'Size',
                          value: _togetherGuestStreamActive
                              ? (_togetherStreamByteLength != null
                                  ? _formatBytes(_togetherStreamByteLength!)
                                  : 'Unknown')
                              : size,
                        ),
                        VideoInfoRow(
                          label: 'Duration',
                          value: _togetherGuestStreamActive
                              ? _formatDuration(_duration)
                              : widget.mediaItem.formattedDuration,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (!_togetherGuestStreamActive)
              ListTile(
                leading: const Icon(
                  Icons.audiotrack_rounded,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                title: const Text(
                  'Extract Audio',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Extracting audio…'),
                      duration: Duration(seconds: 30),
                      backgroundColor: AppColors.surface,
                    ),
                  );
                  final result = await FfmpegService.instance.extractAudio(
                    videoPath: widget.mediaItem.filePath,
                  );
                  messenger.hideCurrentSnackBar();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        result != null
                            ? 'Audio saved: $result'
                            : 'Failed to extract audio',
                      ),
                      backgroundColor:
                          result != null ? AppColors.surface : AppColors.error,
                    ),
                  );
                },
              ),
            if (!_togetherGuestStreamActive)
              ListTile(
                leading: const Icon(
                  Icons.content_cut_rounded,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                title: const Text(
                  'Trim Video',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/tools/whatsapp', extra: widget.mediaItem);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatDuration(Duration value) {
    final h = value.inHours;
    final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _showSpeedPicker() {
    HapticFeedback.selectionClick();
    showSpeedPickerSheet(
      context: context,
      currentSpeed: _playbackSpeed,
      onSpeedSelected: (speed) {
        setState(() => _playbackSpeed = speed);
        _player?.setRate(speed);
      },
    );
  }

  void _showAudioTracks() {
    final player = _player;
    if (player == null) return;
    final audioTracks = player.state.tracks.audio;
    if (audioTracks.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other audio tracks'),
          backgroundColor: AppColors.surface,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VideoAudioTrackSheet(
        tracks: audioTracks,
        activeTrack: player.state.track.audio,
        onSelect: player.setAudioTrack,
      ),
    );
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _player?.setVolume(_isMuted ? 0 : 100);
  }

  void _lockControls() {
    setState(() => _isLocked = true);
    _hideTimer?.cancel();
  }

  void _seekStart(double _) {
    setState(() => _isSeeking = true);
  }

  void _seekChanged(double value) {
    setState(() => _position = Duration(seconds: value.toInt()));
  }

  void _seekEnd(double value) {
    _player?.seek(Duration(seconds: value.toInt()));
    setState(() => _isSeeking = false);
  }

  void _rewind() {
    final next = _position - const Duration(seconds: 10);
    final position = next < Duration.zero ? Duration.zero : next;
    _player?.seek(position);
    setState(() => _position = position);
  }

  Future<void> _previous() async {
    final runtime = NearbyTogetherRuntime.instance;
    if (runtime.active && runtime.isGuest) {
      _showHostControlsQueueMessage();
      return;
    }

    final beforeIndex = ref.read(queueProvider).currentIndex;
    final queue = ref.read(queueProvider.notifier);
    queue.previous();
    final previous = ref.read(queueProvider).current;
    if (previous != null && context.mounted) {
      final opened = await _openQueuedVideo(previous);
      if (!opened && context.mounted) {
        queue.restoreCurrentIndex(beforeIndex);
      }
    }
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _player?.pause();
    } else {
      _player?.play();
    }
  }

  Future<void> _next() async {
    final runtime = NearbyTogetherRuntime.instance;
    if (runtime.active && runtime.isGuest) {
      _showHostControlsQueueMessage();
      return;
    }

    final beforeIndex = ref.read(queueProvider).currentIndex;
    final queue = ref.read(queueProvider.notifier);
    queue.next();
    final next = ref.read(queueProvider).current;
    if (next != null && context.mounted) {
      final opened = await _openQueuedVideo(next);
      if (!opened && context.mounted) {
        queue.restoreCurrentIndex(beforeIndex);
      }
    }
  }

  void _forward() {
    final next = _position + const Duration(seconds: 10);
    final position = next > _duration ? _duration : next;
    _player?.seek(position);
    setState(() => _position = position);
  }

  void _cycleAspectRatio() {
    HapticFeedback.selectionClick();
    setState(
      () => _aspectRatioIndex =
          (_aspectRatioIndex + 1) % _aspectRatioFits.length,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_aspectRatioLabels[_aspectRatioIndex]),
        backgroundColor: AppColors.surface,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _enterPip() {
    HapticFeedback.selectionClick();
    if (_pipSupported) {
      PipService.instance.enterPip();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pop-up not supported'),
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  void _attachPlayer(Player player) {
    if (_player == player) return;
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _player = player;

    _positionSub = player.stream.position.listen((position) {
      if (mounted && !_isSeeking) setState(() => _position = position);
    });
    _durationSub = player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _playingSub = player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
      if (_pipInitialized) {
        unawaited(PipService.instance.setVideoPlaying(playing: playing));
      }
    });

    final nearby = NearbyTogetherRuntime.instance;
    if (nearby.active) nearby.attachPlayer(player);
    final anywhere = AnywhereTogetherRuntime.instance;
    if (anywhere.active) anywhere.attachPlayer(player);
  }

  Future<void> _leavePlayer() async {
    await NearbyTogetherRuntime.instance.stop();
    await AnywhereTogetherRuntime.instance.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    NearbyTogetherRuntime.instance.removeListener(_handleTogetherRuntimeChanged);
    AnywhereTogetherRuntime.instance.removeListener(
      _handleAnywhereTogetherRuntimeChanged,
    );
    final player = _player;
    if (player != null) {
      NearbyTogetherRuntime.instance.detachPlayer(player);
      AnywhereTogetherRuntime.instance.detachPlayer(player);
      PlaybackCoordinator.instance.unregister(player);
    }
    if (!_handoffToAnotherVideo) {
      unawaited(NearbyTogetherRuntime.instance.stop());
      unawaited(AnywhereTogetherRuntime.instance.stop());
      Future.microtask(_restoreOrientation);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          VideoGestureLayer(
            onTap: _toggleControlsVisibility,
            onSeek: (delta) {
              if (_player == null) return;
              final next = _position + delta;
              final position = next < Duration.zero
                  ? Duration.zero
                  : (next > _duration ? _duration : next);
              _player!.seek(position);
              if (mounted) setState(() => _position = position);
            },
            child: MediaKitEngine(
              filePath: widget.mediaItem.filePath,
              title: widget.mediaItem.title,
              startPosition: _savedPosition,
              autoPlay: true,
              fit: _aspectRatioFits[_aspectRatioIndex],
              onPlayerReady: _attachPlayer,
            ),
          ),
          if (!_isLocked)
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 260),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: VideoPlayerControlsOverlay(
                    title: _visibleTitle,
                    ccEnabled: _ccEnabled,
                    isMuted: _isMuted,
                    isPlaying: _isPlaying,
                    position: _position,
                    duration: _duration,
                    playbackSpeed: _playbackSpeed,
                    aspectRatioLabel: _aspectRatioLabels[_aspectRatioIndex],
                    onBack: () => unawaited(_leavePlayer()),
                    onToggleSubtitles: _toggleSubtitles,
                    onAudioTracks: _showAudioTracks,
                    onEqualizer: () {
                      context.push('/player/equalizer');
                    },
                    onMoreOptions: _showMoreOptions,
                    onToggleMute: _toggleMute,
                    onLock: _lockControls,
                    onRotate: _toggleOrientation,
                    onSeekStart: _seekStart,
                    onSeekChanged: _seekChanged,
                    onSeekEnd: _seekEnd,
                    onRewind: _rewind,
                    onPrevious: () => unawaited(_previous()),
                    onPlayPause: _togglePlayback,
                    onNext: () => unawaited(_next()),
                    onForward: _forward,
                    onSpeed: _showSpeedPicker,
                    onAspectRatio: _cycleAspectRatio,
                    onPip: _enterPip,
                  ),
              ),
            ),
          if (!_isLocked)
            TogetherAmbientOverlay(
              controlsVisible: _controlsVisible,
              onOpenConversation: () => unawaited(_showActiveTogetherRoom()),
              listenable: _anywhereTogetherActive
                  ? AnywhereTogetherRuntime.instance
                  : null,
              session: _anywhereTogetherActive
                  ? () => AnywhereTogetherRuntime.instance.state.session
                  : null,
              messages: _anywhereTogetherActive
                  ? () => AnywhereTogetherRuntime.instance.state.messages
                  : null,
              localParticipantId: _anywhereTogetherActive
                  ? () => AnywhereTogetherRuntime.instance.localParticipantId
                  : null,
              active: _anywhereTogetherActive
                  ? () => AnywhereTogetherRuntime.instance.active
                  : null,
            ),
          if (_isLocked)
            VideoPlayerLockOverlay(
              onUnlock: () {
                setState(() => _isLocked = false);
                _resetHideTimer();
              },
            ),
        ],
      ),
    );
  }
}
