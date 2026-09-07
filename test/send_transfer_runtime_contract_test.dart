import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Send keeps authenticated local-only transfer contracts', () {
    final transfer = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/features/transfer/data/transfer_security_policy.dart',
    ).readAsStringSync();

    expect(transfer, contains('WallpaperScaffold('));
    expect(transfer, contains('_sender.startServingBatch('));
    expect(transfer, contains('_receiver.discoverBatch(rawUrl)'));
    expect(transfer, contains('_receiver.download('));
    expect(policy, contains("uri.scheme == 'http'"));
    expect(policy, contains('isPrivateTransferIpv4Host(uri.host)'));
    expect(policy, contains("uri.path != '/batch'"));
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
