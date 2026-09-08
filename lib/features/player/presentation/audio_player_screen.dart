import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../core/database/otya_database.dart';
import '../../../core/services/auto_eq_service.dart';
import '../../../core/services/vault_service.dart';
import '../../../core/services/speed_memory_service.dart';
import '../../../core/services/album_art_service.dart';
import '../../../core/services/audio_handler.dart';
import '../../../core/services/audio_session_service.dart';
import '../../../core/services/playback_coordinator.dart';
import '../../../core/services/media_notification_service.dart';
import '../../../core/services/new_media_tracker.dart';
import '../../../core/services/sleep_detection_service.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../features/settings/settings_provider.dart';
import 'mini_player.dart';
import 'queue_screen.dart';
import 'lyrics_screen.dart';
import 'file_info_sheet.dart';
import 'car_mode_screen.dart';
import 'widgets/sleep_timer.dart';

part 'widgets/audio_player_widgets.dart';
part 'widgets/audio_player_now_playing_view.dart';

enum RepeatState { off, one, all }

class AudioPlayerState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool isLoading;
  final bool hasLoadError;
  final bool isFavorite;
  final RepeatState repeat;

  const AudioPlayerState({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.isLoading = true,
    this.hasLoadError = false,
    this.isFavorite = false,
    this.repeat = RepeatState.off,
  });

  AudioPlayerState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? isLoading,
    bool? hasLoadError,
    bool? isFavorite,
    RepeatState? repeat,
  }) =>
      AudioPlayerState(
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        speed: speed ?? this.speed,
        isLoading: isLoading ?? this.isLoading,
        hasLoadError: hasLoadError ?? this.hasLoadError,
        isFavorite: isFavorite ?? this.isFavorite,
        repeat: repeat ?? this.repeat,
      );
}

class AudioPlayerNotifier extends StateNotifier<AudioPlayerState> {
  final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Otya',
      logLevel: MPVLogLevel.error,
    ),
  );

  String? _currentItemId;
  int _loadGeneration = 0;

  StreamSubscription? _playingSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completedSub;
  ProviderContainer? _container;

  AudioPlayerNotifier() : super(const AudioPlayerState());

  void init() {
    _attachStreams();
    MediaNotificationService.instance.onSkipPrevious = skipPrevious;
    MediaNotificationService.instance.onSkipNext = skipNext;
    SleepDetectionService.instance.onSleepDetected = () {
      debugPrint('[AudioPlayer] Sleep detected — pausing playback.');
      pause();
    };
  }

  void _attachStreams() {
    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      state = state.copyWith(isPlaying: playing);
      if (playing && _currentItemId != null) {
        unawaited(NewMediaTracker.instance.markSeenId(_currentItemId!));
      }
      _updateNotification();
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      if (buffering && state.duration == Duration.zero) {
        state = state.copyWith(isLoading: true);
      } else if (!buffering) {
        state = state.copyWith(isLoading: false);
      }
    });

    var lastSave = DateTime.fromMillisecondsSinceEpoch(0);
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) return;
      state = state.copyWith(position: position);
      if (_currentItemId != null && position.inSeconds > 0) {
        final now = DateTime.now();
        if (now.difference(lastSave).inSeconds >= 5) {
          lastSave = now;
          OtyaDatabase.instance.saveSeekPosition(_currentItemId!, position);
        }
      }
    });

    _durationSub = _player.stream.duration.listen((duration) {
      if (!mounted) return;
      state = state.copyWith(duration: duration);
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed) return;
      if (state.repeat == RepeatState.one) {
        final current = _container?.read(queueProvider).current;
        if (current != null) load(current);
      } else {
        _onTrackComplete();
      }
    });
  }

  void _onTrackComplete() {
    if (_container == null) return;
    final queue = _container!.read(queueProvider);
    final notifier = _container!.read(queueProvider.notifier);
    switch (state.repeat) {
      case RepeatState.one:
        break;
      case RepeatState.all:
        notifier.next();
        final next = _container!.read(queueProvider).current;
        if (next != null) load(next);
        break;
      case RepeatState.off:
        if (queue.currentIndex < queue.items.length - 1) {
          notifier.next();
          final next = _container!.read(queueProvider).current;
          if (next != null) load(next);
        }
        break;
    }
  }

  Future<bool> _loadCurrent(
    MediaItem item, {
    required int generation,
    required double speed,
    Duration? savedPosition,
  }) async {
    bool isCurrent() =>
        _loadGeneration == generation && _currentItemId == item.id;

    try {
      if (!isCurrent()) return false;
      if (_player.state.playing) await _player.pause();
      if (!isCurrent()) return false;

      try {
        await _player.open(Media(item.filePath), play: false);
      } catch (error) {
        debugPrint('[AudioPlayer] player.open failed: $error\nPath: ${item.filePath}');
        if (isCurrent() && mounted) {
          state = state.copyWith(isLoading: false, hasLoadError: true);
        }
        return false;
      }

      if (!isCurrent()) return false;
      await _player.setRate(speed);
      if (!isCurrent()) return false;

      if (savedPosition != null && savedPosition.inSeconds > 0) {
        await _player.seek(savedPosition);
      }
      if (!isCurrent()) return false;

      await PlaybackCoordinator.instance.register(_player, 'audio');
      if (!isCurrent()) return false;
      AudioHandlerSingleton.instance.attachPlayer(_player);
      await AudioSessionService.instance.activate();
      if (!isCurrent()) return false;
      await _player.play();
      return isCurrent();
    } catch (error) {
      debugPrint('[AudioPlayer] load failed: $error');
      if (isCurrent() && mounted) {
        state = state.copyWith(isLoading: false, hasLoadError: true);
      }
      return false;
    }
  }

  Future<void> load(MediaItem item, {AppSettings? settings}) async {
    final generation = ++_loadGeneration;
    _currentItemId = item.id;
    if (mounted) {
      state = state.copyWith(
        isLoading: true,
        hasLoadError: false,
        isFavorite: _loadFavorite(item.id),
      );
    }

    final eqPreset = AutoEqService.instance.detectPreset(item.fileName);
    if (eqPreset.name != 'Flat') {
      unawaited(AutoEqService.instance.applyPreset(eqPreset));
    }
    _container?.read(miniPlayerItemProvider.notifier).state = item;

    final saved = OtyaDatabase.instance.getSeekPosition(item.id);

    try {
      final savedSpeed = await SpeedMemoryService.instance.getSpeed(item.id);
      if (_loadGeneration != generation || _currentItemId != item.id) return;
      final speed = savedSpeed ?? settings?.playbackSpeed ?? state.speed;

      final loaded = await _loadCurrent(
        item,
        generation: generation,
        speed: speed,
        savedPosition: saved,
      );
      if (!loaded ||
          _loadGeneration != generation ||
          _currentItemId != item.id) {
        return;
      }

      if (mounted) {
        state = state.copyWith(
          speed: speed,
          isLoading: false,
          hasLoadError: false,
        );
      }
      _updateNotification();
      OtyaDatabase.instance.recordPlay(item).ignore();
    } catch (error) {
      debugPrint('[AudioPlayer] load error: $error');
      if (_loadGeneration == generation &&
          _currentItemId == item.id &&
          mounted) {
        state = state.copyWith(isLoading: false, hasLoadError: true);
      }
    }
  }

  void _updateNotification() {
    final item = _container?.read(miniPlayerItemProvider);
    if (item == null) return;

    // MediaNotificationService owns artwork resolution, caching and generation
    // ordering. Passing the source value directly avoids a second async layer
    // here that could complete out of order during rapid Next/Previous taps.
    unawaited(
      MediaNotificationService.instance.show(
        id: item.id,
        title: item.title,
        artist: item.artist ?? 'Unknown Artist',
        isPlaying: state.isPlaying,
        albumArtPath: item.albumArtPath,
      ),
    );
  }

  bool _loadFavorite(String id) => OtyaDatabase.instance.getFavoriteFlag(id);

  Future<void> togglePlay() async {
    final willPlay = !state.isPlaying;
    if (willPlay) {
      // A dismissed notification or system Stop action detaches the handler.
      // Reattaching here restores lock-screen, Bluetooth and headset controls
      // before playback resumes without recreating the player.
      AudioHandlerSingleton.instance.attachPlayer(_player);
      await PlaybackCoordinator.instance.register(_player, 'audio');
      await AudioSessionService.instance.activate();
      await _player.play();
    } else {
      await _player.pause();
    }
  }

  void pause() => _player.pause();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skipForward() =>
      _player.seek(state.position + const Duration(seconds: 10));

  Future<void> skipBack() {
    final target = state.position - const Duration(seconds: 10);
    return _player.seek(target.isNegative ? Duration.zero : target);
  }

  void skipNext() {
    if (_container == null) return;
    if (_currentItemId != null) {
      OtyaDatabase.instance.saveSeekPosition(_currentItemId!, state.position);
    }
    _container!.read(queueProvider.notifier).next();
    final next = _container!.read(queueProvider).current;
    if (next != null) load(next);
  }

  void skipPrevious() {
    if (state.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    if (_container == null) return;
    if (_currentItemId != null) {
      OtyaDatabase.instance.saveSeekPosition(_currentItemId!, Duration.zero);
    }
    _container!.read(queueProvider.notifier).previous();
    final previous = _container!.read(queueProvider).current;
    if (previous != null) load(previous);
  }

  void setSpeed(double speed) {
    _player.setRate(speed);
    state = state.copyWith(speed: speed);
    if (_currentItemId != null) {
      SpeedMemoryService.instance.saveSpeed(_currentItemId!, speed);
    }
  }

  void toggleFavorite() {
    final next = !state.isFavorite;
    state = state.copyWith(isFavorite: next);
    if (_currentItemId != null) {
      OtyaDatabase.instance.setFavoriteFlag(_currentItemId!, next);
    }
  }

  void toggleShuffle() {
    _container?.read(queueProvider.notifier).toggleShuffle();
  }

  void cycleRepeat() {
    final next = RepeatState.values[
        (state.repeat.index + 1) % RepeatState.values.length];
    state = state.copyWith(repeat: next);
  }

  void savePosition(String id) =>
      OtyaDatabase.instance.saveSeekPosition(id, state.position);

  @override
  void dispose() {
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    MediaNotificationService.instance.onSkipPrevious = null;
    MediaNotificationService.instance.onSkipNext = null;
    SleepDetectionService.instance.onSleepDetected = null;
    PlaybackCoordinator.instance.unregister(_player);
    MediaNotificationService.instance.dismiss();
    AudioHandlerSingleton.instance.detachPlayer();
    _player.dispose();
    super.dispose();
  }
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>((ref) {
  final notifier = AudioPlayerNotifier();
  notifier._container = ref.container;
  notifier.init();
  return notifier;
});

class AudioPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem mediaItem;
  final bool resumeOnly;

  const AudioPlayerScreen({
    super.key,
    required this.mediaItem,
    this.resumeOnly = false,
  });

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen>
    with WidgetsBindingObserver {
  bool _showRetry = false;
  Timer? _loadTimeoutTimer;

  MediaItem get _activeItem =>
      ref.read(miniPlayerItemProvider) ?? widget.mediaItem;

  void _startLoad([MediaItem? requestedItem]) {
    final item = requestedItem ?? _activeItem;
    _showRetry = false;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && ref.read(audioPlayerProvider).isLoading) {
        setState(() => _showRetry = true);
      }
    });
    ref.read(audioPlayerProvider.notifier).load(
          item,
          settings: ref.read(settingsProvider),
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.resumeOnly) _startLoad(widget.mediaItem);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(audioPlayerProvider.notifier).savePosition(_activeItem.id);
    }
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    ref.read(audioPlayerProvider.notifier).savePosition(_activeItem.id);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showQueue() => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => const QueueScreen(),
      );

  void _showLyrics(MediaItem item, Duration position) => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => LyricsSheet(item: item, position: position),
      );

  void _showFileInfo(MediaItem item) => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => FileInfoSheet(item: item),
      );

  void _showOptions(MediaItem item) => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (_) => _OptionsSheet(
          mediaItem: item,
          onFileInfo: () {
            Navigator.pop(context);
            _showFileInfo(item);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final activeItem = ref.watch(miniPlayerItemProvider) ?? widget.mediaItem;
    final isShuffle = ref.watch(queueProvider.select((queue) => queue.shuffle));
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenHeight < 680;
    final isMedium = screenHeight < 780;
    final isTablet = screenWidth > 600;
    final artPadding =
        isTablet ? 80.0 : isSmall ? 12.0 : isMedium ? 24.0 : 36.0;
    final playButtonSize = isTablet ? 80.0 : isSmall ? 56.0 : 68.0;
    final skipIconSize = isTablet ? 34.0 : isSmall ? 24.0 : 30.0;
    final spacing = isSmall ? 4.0 : isMedium ? 8.0 : 16.0;
    final showRetry = _showRetry || playerState.hasLoadError;

    return _AudioPlayerNowPlayingView(
      activeItem: activeItem,
      playerState: playerState,
      isShuffle: isShuffle,
      showRetry: showRetry,
      artPadding: artPadding,
      playButtonSize: playButtonSize,
      skipIconSize: skipIconSize,
      spacing: spacing,
      speedLabel: _formatSpeed(playerState.speed),
      onBack: () => Navigator.of(context).pop(),
      onSleepExpire: () => ref.read(audioPlayerProvider.notifier).pause(),
      onOptions: () => _showOptions(activeItem),
      onSwipeNext: () => ref.read(audioPlayerProvider.notifier).skipNext(),
      onSwipePrevious: () =>
          ref.read(audioPlayerProvider.notifier).skipPrevious(),
      onFavorite: () =>
          ref.read(audioPlayerProvider.notifier).toggleFavorite(),
      onSeek: (position) =>
          ref.read(audioPlayerProvider.notifier).seek(position),
      onShuffle: () => ref.read(audioPlayerProvider.notifier).toggleShuffle(),
      onSpeed: () {
        const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        final index = speeds.indexOf(playerState.speed);
        ref
            .read(audioPlayerProvider.notifier)
            .setSpeed(speeds[(index + 1) % speeds.length]);
      },
      onRepeat: () => ref.read(audioPlayerProvider.notifier).cycleRepeat(),
      onPrevious: () =>
          ref.read(audioPlayerProvider.notifier).skipPrevious(),
      onSkipBack: () => ref.read(audioPlayerProvider.notifier).skipBack(),
      onPlayPause: () {
        if (showRetry) {
          setState(() => _showRetry = false);
          _startLoad(activeItem);
        } else {
          HapticFeedback.mediumImpact();
          ref.read(audioPlayerProvider.notifier).togglePlay();
        }
      },
      onSkipForward: () =>
          ref.read(audioPlayerProvider.notifier).skipForward(),
      onNext: () => ref.read(audioPlayerProvider.notifier).skipNext(),
      onLyrics: () => _showLyrics(activeItem, playerState.position),
      onEqualizer: () => context.push('/player/equalizer'),
      onQueue: _showQueue,
      onShare: () => Share.shareXFiles(
        [XFile(activeItem.filePath)],
        text: activeItem.title,
      ),
    );
  }

  String _formatSpeed(double speed) => speed == speed.truncateToDouble()
      ? '${speed.toInt()}x'
      : '${speed}x';
}
