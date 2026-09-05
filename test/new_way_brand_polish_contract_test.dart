import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android notification surfaces use the canonical Otya brand', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final channels = File(
      'lib/core/services/shared_notification_plugin.dart',
    ).readAsStringSync();
    final push = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(
      mainSource,
      contains("androidNotificationChannelName: 'Otya — Now Playing'"),
    );
    expect(mainSource, contains('notificationColor: AppColors.brandBlue'));
    expect(channels, contains("'Otya — Updates'"));
    expect(channels, contains("'Otya — Announcements'"));
    expect(channels, contains("'Otya Tools — Progress'"));
    expect(channels, contains("'Otya Tools — Complete'"));
    expect(channels, contains("'Otya Tools — Errors'"));
    expect(push, contains("'Otya — Updates'"));
    expect(push, contains("contentTitle: 'Otya \$version is available'"));
    expect(push, contains("'Otya — Announcements'"));
    expect(push, contains("uri.scheme != 'https'"));
    expect(push, contains("host.endsWith('.\$_officialHost')"));
    expect(mainSource, isNot(contains("androidNotificationChannelName: 'OTYA")));
  });

  test('Otya uses the approved current mark and cyan-blue palette', () {
    final colors = File('lib/app/theme/app_colors.dart').readAsStringSync();
    final logo = File('lib/shared/widgets/otya_logo_v2.dart').readAsStringSync();
    final brandNote = File(
      'assets/branding/README-current-mark.md',
    ).readAsStringSync();

    expect(colors, contains('Color(0xFF27E8FF)'));
    expect(colors, contains('Color(0xFF126BFF)'));
    expect(colors, contains('Color(0xFF173BFF)'));
    expect(logo, contains('assets/branding/otya_mark_current.png'));
    expect(logo, contains("'Otya'"));
    expect(brandNote, contains('current owner-approved cyan/blue Otya app icon'));
    expect(brandNote, contains('Do not restore the retired'));
  });

  test('Together join keeps network details behind user-facing language', () {
    final source = File(
      'lib/features/together/presentation/nearby_together_join_sheet.dart',
    ).readAsStringSync();

    expect(source, contains("hintText: 'Paste the invite here'"));
    expect(source, contains('Otya reuses what you already watched'));
    expect(source, contains('The video stays between your phones.'));
    expect(source, isNot(contains("hintText: 'ws://")));
    expect(source, isNot(contains('Reuse watched bytes')));
    expect(source, isNot(contains('OTYA reuses what you already watched')));
  });
}
