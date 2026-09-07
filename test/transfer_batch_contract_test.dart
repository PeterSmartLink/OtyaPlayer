import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Send serves one authenticated batch without temporary archives', () {
    final sender = File(
      'lib/features/transfer/data/media_sender.dart',
    ).readAsStringSync();
    final receiver = File(
      'lib/features/transfer/data/media_receiver.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/features/transfer/data/transfer_security_policy.dart',
    ).readAsStringSync();

    expect(sender, contains('startServingBatch'));
    expect(sender, contains(r'/batch?t=${session.token}'));
    expect(sender, contains(r'/media/$i?t=$token'));
    expect(sender, contains("'files': items"));
    expect(sender, isNot(contains('ZipFile')));
    expect(sender, isNot(contains('.zip')));

    expect(receiver, contains('discoverBatch'));
    expect(receiver, contains('OtyaTransferBatchItem'));
    expect(receiver, contains('X-Otya-Transfer-Mode'));
    expect(receiver, contains('itemUri.host != uri.host'));
    expect(receiver, contains("itemUri.queryParameters['t'] != token"));

    expect(policy, contains('isAllowedTransferBatchUri'));
    expect(policy, contains(r"RegExp(r'^/media/[0-9]+$')"));
  });

  test('received batches are bounded as a whole and cannot repeat one URL', () {
    final receiver = File(
      'lib/features/transfer/data/media_receiver.dart',
    ).readAsStringSync();

    expect(receiver, contains('_maxBatchItems = 200'));
    expect(receiver, contains('_maxBatchBytes = 64 * 1024 * 1024 * 1024'));
    expect(receiver, contains('final seenUrls = <String>{}'));
    expect(receiver, contains('if (!seenUrls.add(normalizedUrl))'));
    expect(receiver, contains('totalBatchBytes += size'));
    expect(receiver, contains('if (totalBatchBytes > _maxBatchBytes)'));
  });

  test('Receive preflights Android storage before opening the destination sink', () {
    final receiver = File(
      'lib/features/transfer/data/media_receiver.dart',
    ).readAsStringSync();
    final bridge = File(
      'packages/otya_transfer_android/lib/otya_transfer_android.dart',
    ).readAsStringSync();
    final android = File(
      'packages/otya_transfer_android/android/src/main/kotlin/com/petersmartlink/otya_transfer_android/OtyaTransferAndroidPlugin.kt',
    ).readAsStringSync();

    expect(receiver, contains('_storageReserveBytes = 64 * 1024 * 1024'));
    expect(receiver, contains('OtyaTransferAndroid.availableBytes'));
    expect(receiver, contains('InsufficientTransferStorageException'));
    expect(
      receiver.indexOf('OtyaTransferAndroid.availableBytes'),
      lessThan(receiver.indexOf('sink = saveFile.openWrite')),
    );
    expect(bridge, contains("'availableBytes'"));
    expect(android, contains('"availableBytes" -> availableBytes(call, result)'));
    expect(android, contains('StatFs(target.absolutePath).availableBytes'));
  });

  test('Send selection is multi-item and survives Videos Music switching', () {
    final screen = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();

    expect(screen, contains('final Map<String, MediaItem> _selectedMedia'));
    expect(screen, contains('_toggleSelection(MediaItem item)'));
    expect(screen, contains('_toggleAllVisible(List<MediaItem> visible)'));
    expect(screen, contains('_sender.startServingBatch('));
    expect(screen, contains('Tap as many items as you want'));
    expect(screen, contains('Your selection stays when you switch between Videos and Music'));
    expect(screen, contains("label: 'Videos'"));
    expect(screen, contains("label: 'Music'"));
    expect(screen, contains("label: Text(busy ? 'Preparing' : 'Send \$count')"));
  });

  test('Send Receive mode control is anchored after the content, not above it', () {
    final screen = File(
      'lib/features/transfer/presentation/transfer_screen.dart',
    ).readAsStringSync();

    final bodyStart = screen.indexOf('body: SafeArea(');
    final expanded = screen.indexOf('Expanded(', bodyStart);
    final modeSwitch = screen.indexOf('_ModeSwitch(mode: _mode', bodyStart);

    expect(bodyStart, greaterThanOrEqualTo(0));
    expect(expanded, greaterThan(bodyStart));
    expect(modeSwitch, greaterThan(expanded));
    expect(
      screen.substring(bodyStart, modeSwitch),
      isNot(contains('child: _ModeSwitch(mode: _mode')),
    );
  });
}
