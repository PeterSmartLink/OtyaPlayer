import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy assistant compatibility uses the approved Otya mark', () {
    final mark = File('lib/shared/widgets/otya_ai_mark.dart').readAsStringSync();
    final exports = File('lib/shared/widgets/otya_logo.dart').readAsStringSync();

    expect(mark, contains('OtyaMark(size: size)'));
    expect(mark, contains('OtyaMark(size: markSize)'));
    expect(mark, contains('AppColors.brandCyan'));
    expect(mark, contains('AppColors.brandBlue'));
    expect(mark, isNot(contains('Color(0xFFFF3B30)')));
    expect(mark, isNot(contains('Color(0xFFFFD60A)')));
    expect(mark, isNot(contains('three equal balls')));
    expect(exports, contains('must not introduce a second public logo or color system'));
  });

  test('legacy assistant compatibility and Send keep their core runtime contracts', () {
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
    expect(transfer, contains('_sender.startServing(item.filePath)'));
    expect(transfer, contains('_receiver.download('));
    expect(transfer, contains("uri.scheme != 'http'"));
    expect(transfer, contains('_isPrivateHost(uri.host)'));
    expect(transfer, contains('MobileScanner('));
  });
}
