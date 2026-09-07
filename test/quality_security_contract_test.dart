import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OTYA keeps expensive duplicate detection off the UI isolate', () {
    final source = File(
      'lib/features/my_space/presentation/providers/my_space_provider.dart',
    ).readAsStringSync();
    expect(source, contains('Isolate.run<List<List<String>>>'));
    expect(source, contains('unawaited(_detectDuplicates(fresh))'));
  });

  test('OTYA custom wallpapers request bounded decode dimensions', () {
    final source =
        File('lib/shared/widgets/wallpaper_scaffold.dart').readAsStringSync();
    expect(source, contains('cacheWidth: decodeWidth'));
    expect(source, contains('cacheHeight: decodeHeight'));
  });

  test('OTYA Transfer rejects arbitrary cleartext internet URLs', () {
    final policy = File(
      'lib/features/transfer/data/transfer_security_policy.dart',
    ).readAsStringSync();
    final receiver = File(
      'lib/features/transfer/data/media_receiver.dart',
    ).readAsStringSync();

    expect(receiver, contains('isAllowedTransferUri(uri)'));
    expect(policy, contains("uri.scheme == 'http'"));
    expect(
      policy,
      contains("uri.path == '/media' || _indexedMediaPathPattern.hasMatch(uri.path)"),
    );
    expect(policy, contains("uri.path != '/batch'"));
    expect(policy, contains("RegExp(r'^[a-f0-9]{64}\$')"));
    expect(policy, contains('(a == 192 && b == 168)'));
  });

  test('OTYA WebView and updater are confined to official HTTPS origins', () {
    final webview = File(
      'lib/features/webview/otya_webview_screen.dart',
    ).readAsStringSync();
    final updater =
        File('lib/core/widgets/update_dialog.dart').readAsStringSync();

    for (final source in [webview, updater]) {
      expect(source, contains("'petersmartlink.com'"));
      expect(source, contains("'www.petersmartlink.com'"));
      expect(
        source.contains("uri.scheme == 'https'") ||
            source.contains("uri.scheme != 'https'"),
        isTrue,
      );
    }
  });
}
