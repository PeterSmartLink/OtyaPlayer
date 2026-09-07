import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Send keeps authenticated local-only transfer contracts', () {
    final transfer = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();

    expect(transfer, contains('WallpaperScaffold('));
    expect(transfer, contains('_sender.startServing(item.filePath)'));
    expect(transfer, contains('_receiver.download('));
    expect(transfer, contains("uri.scheme != 'http'"));
    expect(transfer, contains('_isPrivateHost(uri.host)'));
    expect(transfer, contains('MobileScanner('));
  });

  test('Android product source does not keep a consumer AI implementation', () {
    expect(File('lib/features/ai/otya_support_screen.dart').existsSync(), isFalse);
    expect(File('lib/features/ai/otya_support_screen_v3.dart').existsSync(), isFalse);
    expect(File('lib/core/services/otya_support_service.dart').existsSync(), isFalse);
    expect(File('lib/shared/widgets/otya_ai_mark.dart').existsSync(), isFalse);

    final logo = File('lib/shared/widgets/otya_logo.dart').readAsStringSync();
    expect(logo, isNot(contains('otya_ai_mark.dart')));
  });
}
