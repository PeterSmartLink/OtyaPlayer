import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final video = File('lib/features/player/presentation/video_player_screen.dart').readAsStringSync();
  final notifications = File('lib/core/services/media_notification_service.dart').readAsStringSync();

  test('video owns Android MediaSession while its player is active', () {
    expect(video.contains('AudioHandlerSingleton.instance.attachPlayer(player)'), isTrue);
    expect(video.contains('MediaNotificationService.instance.show('), isTrue);
    expect(video.contains('MediaNotificationService.instance.updatePlayState(playing)'), isTrue);
    expect(video.contains('AudioSessionService.instance.activate()'), isTrue);
  });

  test('video transport callbacks restore the previous media owner', () {
    expect(notifications.contains('registerTransportCallbacks('), isTrue);
    expect(notifications.contains('unregisterTransportCallbacks(Object owner)'), isTrue);
    expect(video.contains('onSkipPrevious: () => unawaited(_previous())'), isTrue);
    expect(video.contains('onSkipNext: () => unawaited(_next())'), isTrue);
    expect(video.contains('MediaNotificationService.instance.unregisterTransportCallbacks(this)'), isTrue);
  });

  test('leaving video clears stale system playback state', () {
    expect(video.contains('AudioHandlerSingleton.instance.detachPlayer()'), isTrue);
    expect(video.contains('MediaNotificationService.instance.dismiss()'), isTrue);
    expect(video.contains('AudioSessionService.instance.deactivate()'), isTrue);
  });
}
