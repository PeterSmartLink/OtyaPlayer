import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video gestures keep the centre calm and show feedback near the gesture', () {
    final source = File(
      'lib/features/player/presentation/widgets/video_gesture_layer.dart',
    ).readAsStringSync();

    expect(source, contains('static const double _edgeGestureFraction = .38'));
    expect(source, contains('final inLeft = start.dx <= size.width * _edgeGestureFraction'));
    expect(
      source,
      contains('start.dx >= size.width * (1 - _edgeGestureFraction)'),
    );
    expect(source, contains('_hudCenterY = start.dy'));
    expect(source, contains('_seekCenterY = atY'));
    expect(source, isNot(contains('child: Center(\n                    child: ValueListenableBuilder<double>')));
    expect(
      source,
      isNot(contains('Positioned.fill(child: IgnorePointer(child: _SeekRipple')),
    );
  });

  test('Together conversation stays translucent and adapts to screen/keyboard', () {
    final source = File(
      'lib/features/together/presentation/nearby_together_live_surface.dart',
    ).readAsStringSync();

    expect(source, contains('backgroundColor: Colors.transparent'));
    expect(source, contains('barrierColor: Colors.black.withValues(alpha: .08)'));
    expect(source, contains('ImageFilter.blur(sigmaX: 22, sigmaY: 22)'));
    expect(source, contains('final keyboardOpen = media.viewInsets.bottom > 0'));
    expect(source, contains('alignment: Alignment.bottomRight'));
    expect(source, contains('alignment: Alignment.bottomCenter'));
    expect(source, contains('surfaceContainerHighest:'));
    expect(source, contains('withValues(alpha: .48)'));
    expect(source, isNot(contains('heightFactor: .64')));
    expect(source, isNot(contains('withValues(alpha: .98)')));
  });
}
