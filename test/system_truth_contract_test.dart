import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video uses one pointer owner for tap and swipe gestures', () {
    final player = File(
      'lib/features/player/presentation/video_player_screen.dart',
    ).readAsStringSync();
    final gestures = File(
      'lib/features/player/presentation/widgets/video_gesture_layer.dart',
    ).readAsStringSync();

    expect(player, contains('onTap: _toggleControlsVisibility'));
    expect(gestures, contains('final VoidCallback? onTap;'));
    expect(gestures, contains('onTap: widget.onTap'));
    expect(player, contains('void _toggleControlsVisibility()'));
    expect(
      player,
      isNot(
        contains(
          'behavior: HitTestBehavior.translucent,\n                  onTap: _resetHideTimer',
        ),
      ),
    );
    expect(
      player,
      isNot(
        contains(
          'if (!_controlsVisible && !_isLocked)\n            Positioned.fill(',
        ),
      ),
    );
  });

  test('in-app browser matches exact PeterSmart Link production surfaces', () {
    final browser = File(
      'lib/features/webview/otya_webview_screen.dart',
    ).readAsStringSync();

    for (final host in [
      'petersmartlink.com',
      'www.petersmartlink.com',
      'space.petersmartlink.com',
      'docs.petersmartlink.com',
      'status.petersmartlink.com',
    ]) {
      expect(browser, contains("'$host'"));
    }
    expect(browser, contains("path.startsWith('/apk/')"));
    expect(browser, contains('LaunchMode.externalApplication'));
  });

  test('direct updater accepts only one coherent published release identity', () {
    final updates = File('lib/core/services/update_service.dart').readAsStringSync();
    final dialog = File('lib/core/widgets/update_dialog.dart').readAsStringSync();

    expect(updates, contains("data['published'] != true"));
    expect(
      updates,
      contains("r'^v(\\d+\\.\\d+\\.\\d+)\\+([1-9]\\d*)\$'"),
    );
    expect(updates, contains('tagMatch.group(1) != serverVersion'));
    expect(updates, contains('tagBuild != serverVersionCode'));
    expect(
      updates,
      contains(
        "final exactKey = abi == 'arm64' ? 'exactArm64' : 'exactArm32'",
      ),
    );
    expect(
      updates,
      contains('Updates for this build are managed by Google Play.'),
    );
    expect(dialog, contains("router.push(\n      '/webview'"));
    expect(dialog, isNot(contains('LaunchMode.externalApplication')));
  });
}
