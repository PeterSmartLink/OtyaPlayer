import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Next uses the approved Otya mark instead of a second logo', () {
    final mark = File('lib/shared/widgets/otya_ai_mark.dart').readAsStringSync();
    final exports = File('lib/shared/widgets/otya_logo.dart').readAsStringSync();

    expect(mark, contains('OtyaMark(size: size)'));
    expect(mark, contains('OtyaMark(size: markSize)'));
    expect(mark, contains('AppColors.brandCyan'));
    expect(mark, contains('AppColors.brandBlue'));
    expect(mark, isNot(contains('Color(0xFFFF3B30)')));
    expect(mark, isNot(contains('Color(0xFFFFD60A)')));
    expect(mark, isNot(contains('three equal balls')));
    expect(exports, contains('not a separate logo or color system'));
  });

  test('Next and Transfer use the shared branded surface without changing their core contracts', () {
    final next = File(
      'lib/features/ai/otya_support_screen_v3.dart',
    ).readAsStringSync();
    final transfer = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();

    expect(next, contains('WallpaperScaffold('));
    expect(next, contains('_service.askStream('));
    expect(next, contains('_service.handoff('));
    expect(next, contains('OtyaThinkingMark'));

    expect(transfer, contains('WallpaperScaffold('));
    expect(transfer, contains('_serveMedia(item)'));
    expect(transfer, contains('_sender.startServing('));
    expect(transfer, contains('_receiver.download('));
    expect(transfer, contains('isAllowedTransferUri(uri)'));
    expect(transfer, contains('TransferHotspotService.instance.start()'));
    expect(transfer, contains('Receive without Otya'));
    expect(transfer, contains('MobileScanner('));
  });
}
