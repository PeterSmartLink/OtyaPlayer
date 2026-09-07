import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<void> expectImageDecodes(String path) async {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path must exist');
  final bytes = await file.readAsBytes();
  expect(bytes.length, greaterThan(32), reason: '$path must not be empty');
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(0));
    expect(frame.image.height, greaterThan(0));
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical Otya app icon is a decodable image, not just a container', () async {
    await expectImageDecodes('assets/branding/otya_app_icon.webp');
  });

  test('active Otya visual pipeline does not depend on known broken binaries', () {
    final logo = File('lib/shared/widgets/otya_logo_v2.dart').readAsStringSync();
    final launcher = File(
      'android/app/src/main/res/drawable/otya_launcher_foreground.xml',
    ).readAsStringSync();

    expect(logo, isNot(contains('otya_mark_current.png')));
    expect(launcher, isNot(contains('otya_launcher_foreground_bitmap')));
  });
}
