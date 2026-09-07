import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/playback_coordinator.dart';

/// Gesture layer for the video player.
///
/// Left edge vertical swipe  → brightness
/// Right edge vertical swipe → volume
/// Double-tap left/right     → seek ±10 seconds
/// Horizontal fling          → seek ±10 seconds
/// Long press                → real 2× playback while held
///
/// The middle of the video is deliberately left calm for playback controls.
/// Feedback appears close to the gesture origin instead of floating in the
/// centre of the picture, which keeps faces/subtitles visible on small phones.
class VideoGestureLayer extends StatefulWidget {
  final Widget child;
  final void Function(Duration delta)? onSeek;

  const VideoGestureLayer({
    super.key,
    required this.child,
    this.onSeek,
  });

  @override
  State<VideoGestureLayer> createState() => _VideoGestureLayerState();
}

class _VideoGestureLayerState extends State<VideoGestureLayer> {
  static const _brightnessChannel =
      MethodChannel('com.otyaplayer.app/brightness');
  static const _volumeChannel = MethodChannel('com.otyaplayer.app/volume');

  // Keep the central 24% of the video free of brightness/volume gestures.
  static const double _edgeGestureFraction = .38;

  final _brightness = ValueNotifier<double>(0.5);
  final _volume = ValueNotifier<double>(0.5);
  final _showBrightness = ValueNotifier<bool>(false);
  final _showVolume = ValueNotifier<bool>(false);

  Timer? _hudTimer;
  Timer? _seekTimer;
  bool _showSeekRipple = false;
  bool _seekForward = true;
  bool _speedBoosted = false;
  Offset? _dragStart;
  double _horizontalDrag = 0;
  bool _dragIsVertical = false;
  bool _dragDirectionLocked = false;
  double _hudCenterY = 0;
  double _seekCenterY = 0;

  @override
  void initState() {
    super.initState();
    _readInitialValues();
  }

  Future<void> _readInitialValues() async {
    try {
      final b = await _brightnessChannel.invokeMethod<double>('getBrightness');
      if (b != null) _brightness.value = b < 0 ? 0.5 : b.clamp(0.0, 1.0);
    } catch (_) {}
    try {
      final v = await _volumeChannel.invokeMethod<double>('getVolume');
      if (v != null) _volume.value = v.clamp(0.0, 1.0);
    } catch (_) {}
  }

  void _scheduleHudHide() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1100), () {
      _showBrightness.value = false;
      _showVolume.value = false;
    });
  }

  Future<void> _applyBrightness(double delta) async {
    final next = (_brightness.value + delta).clamp(0.0, 1.0);
    _brightness.value = next;
    _showBrightness.value = true;
    _showVolume.value = false;
    try {
      await _brightnessChannel.invokeMethod('setBrightness', {'value': next});
    } catch (_) {}
    _scheduleHudHide();
  }

  Future<void> _applyVolume(double delta) async {
    final next = (_volume.value + delta).clamp(0.0, 1.0);
    _volume.value = next;
    _showVolume.value = true;
    _showBrightness.value = false;
    try {
      await _volumeChannel.invokeMethod('setVolume', {'value': next});
    } catch (_) {}
    _scheduleHudHide();
  }

  void _seek(bool forward, {double? atY}) {
    if (widget.onSeek == null) return;
    widget.onSeek!(Duration(seconds: forward ? 10 : -10));
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _seekForward = forward;
      _seekCenterY = atY ??
          _dragStart?.dy ??
          MediaQuery.sizeOf(context).height * .5;
      _showSeekRipple = true;
    });
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 560), () {
      if (mounted) setState(() => _showSeekRipple = false);
    });
  }

  void _handleDoubleTap(Offset position, Size size, EdgeInsets safe) {
    final topGuard = (safe.top + 24).clamp(32.0, 68.0);
    final bottomGuard = (safe.bottom + 34).clamp(44.0, 82.0);
    if (position.dy < topGuard || position.dy > size.height - bottomGuard) {
      return;
    }

    // A double tap in the calm centre does not accidentally seek. Only the
    // natural left/right seek zones respond.
    if (position.dx <= size.width * _edgeGestureFraction) {
      _seek(false, atY: position.dy);
    } else if (position.dx >= size.width * (1 - _edgeGestureFraction)) {
      _seek(true, atY: position.dy);
    }
  }

  Future<void> _beginSpeedBoost() async {
    final ok = await PlaybackCoordinator.instance.beginSpeedBoost(rate: 2.0);
    if (!ok || !mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _speedBoosted = true);
  }

  Future<void> _endSpeedBoost() async {
    if (!_speedBoosted) return;
    await PlaybackCoordinator.instance.endSpeedBoost();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _speedBoosted = false);
  }

  void _onPanStart(DragStartDetails details) {
    _dragStart = details.localPosition;
    _horizontalDrag = 0;
    _dragIsVertical = false;
    _dragDirectionLocked = false;
  }

  void _onPanUpdate(DragUpdateDetails details, Size size, EdgeInsets safe) {
    final start = _dragStart;
    if (start == null) return;

    final topGuard = (safe.top + 28).clamp(36.0, 72.0);
    final bottomGuard = (safe.bottom + 40).clamp(48.0, 88.0);
    if (start.dy < topGuard || start.dy > size.height - bottomGuard) return;

    if (!_dragDirectionLocked) {
      final total = details.localPosition - start;
      if (total.distance < 7) return;
      _dragIsVertical = total.dy.abs() > total.dx.abs() * 1.15;
      _dragDirectionLocked = true;
      if (_dragIsVertical) {
        final inLeft = start.dx <= size.width * _edgeGestureFraction;
        final inRight =
            start.dx >= size.width * (1 - _edgeGestureFraction);
        if (!inLeft && !inRight) return;
        _hudCenterY = start.dy;
      }
    }

    if (_dragIsVertical) {
      final inLeft = start.dx <= size.width * _edgeGestureFraction;
      final inRight = start.dx >= size.width * (1 - _edgeGestureFraction);
      if (!inLeft && !inRight) return;
      final delta =
          -details.delta.dy / (size.height * 0.42).clamp(180.0, 360.0);
      if (inLeft) {
        _applyBrightness(delta);
      } else if (inRight) {
        _applyVolume(delta);
      }
    } else {
      _horizontalDrag += details.delta.dx;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dragDirectionLocked && !_dragIsVertical) {
      final velocity = details.velocity.pixelsPerSecond.dx;
      if (_horizontalDrag.abs() >= 54 || velocity.abs() >= 520) {
        _seek(
          _horizontalDrag != 0 ? _horizontalDrag > 0 : velocity > 0,
          atY: _dragStart?.dy,
        );
      }
    }
    _dragStart = null;
    _horizontalDrag = 0;
    _dragDirectionLocked = false;
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _seekTimer?.cancel();
    if (_speedBoosted) PlaybackCoordinator.instance.endSpeedBoost();
    _brightness.dispose();
    _volume.dispose();
    _showBrightness.dispose();
    _showVolume.dispose();
    super.dispose();
  }

  double _hudTop(Size size, EdgeInsets safe) {
    const estimatedHudHeight = 158.0;
    final minTop = safe.top + 12;
    final maxTop = mathMax(minTop, size.height - safe.bottom - estimatedHudHeight - 12);
    return (_hudCenterY - estimatedHudHeight / 2).clamp(minTop, maxTop);
  }

  double _seekTop(Size size, EdgeInsets safe) {
    const diameter = 72.0;
    final minTop = safe.top + 18;
    final maxTop = mathMax(minTop, size.height - safe.bottom - diameter - 18);
    return (_seekCenterY - diameter / 2).clamp(minTop, maxTop);
  }

  static double mathMax(double a, double b) => a > b ? a : b;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final safe = media.padding;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: (details) =>
                _handleDoubleTap(details.localPosition, size, safe),
            onPanStart: _onPanStart,
            onPanUpdate: (d) => _onPanUpdate(d, size, safe),
            onPanEnd: _onPanEnd,
            onPanCancel: () {
              _dragStart = null;
              _horizontalDrag = 0;
              _dragDirectionLocked = false;
            },
            onLongPressStart: (_) => _beginSpeedBoost(),
            onLongPressEnd: (_) => _endSpeedBoost(),
            onLongPressCancel: _endSpeedBoost,
          ),
        ),
        if (_speedBoosted)
          Positioned(
            top: safe.top + 18,
            left: 0,
            right: 0,
            child: const Center(
              child: _StatusPill(
                icon: Icons.fast_forward_rounded,
                label: '2× Speed',
              ),
            ),
          ),
        if (_showSeekRipple)
          Positioned(
            left: _seekForward ? null : 22,
            right: _seekForward ? 22 : null,
            top: _seekTop(size, safe),
            child: IgnorePointer(
              child: _SeekRipple(forward: _seekForward),
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: _showBrightness,
          builder: (_, show, __) => show
              ? Positioned(
                  left: 14,
                  top: _hudTop(size, safe),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _brightness,
                    builder: (_, value, __) => _GlassHud(
                      icon: Icons.brightness_6_rounded,
                      value: value,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _showVolume,
          builder: (_, show, __) => show
              ? Positioned(
                  right: 14,
                  top: _hudTop(size, safe),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _volume,
                    builder: (_, value, __) => _GlassHud(
                      icon: value == 0
                          ? Icons.volume_off_rounded
                          : value < 0.5
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      value: value,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: .58),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.brandCyan.withValues(alpha: .28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.brandCyan, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _GlassHud extends StatelessWidget {
  final IconData icon;
  final double value;
  const _GlassHud({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 56,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: .58),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.brandCyan.withValues(alpha: .24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.brandCyan, size: 20),
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  width: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: .12)),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: value.clamp(0.0, 1.0),
                            child: Container(color: AppColors.brandCyan),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SeekRipple extends StatelessWidget {
  final bool forward;
  const _SeekRipple({required this.forward});

  @override
  Widget build(BuildContext context) => ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface.withValues(alpha: .50),
              border: Border.all(
                color: AppColors.brandCyan.withValues(alpha: .40),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  forward
                      ? Icons.forward_10_rounded
                      : Icons.replay_10_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(height: 2),
                Text(
                  forward ? '+10s' : '-10s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
