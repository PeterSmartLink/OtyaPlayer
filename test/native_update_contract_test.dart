import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('update notifications never launch a web destination', () {
    final push = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();
    final fcm = File('lib/core/services/fcm_service.dart').readAsStringSync();

    expect(
      push,
      contains("static const _nativeUpdatePayload = '\${_prefixUpdate}native';"),
    );
    expect(push, contains('UpdateDialog.checkAndShow(context, forceCheck: true)'));
    expect(push, isNot(contains('required String downloadUrl')));
    expect(push, isNot(contains("payload: safeUrl.isNotEmpty ?")));
    expect(fcm, contains("payload: 'update:native'"));

    final foregroundStart = fcm.indexOf("if (type == 'update')");
    final foregroundEnd = fcm.indexOf(
      'await PushNotificationService.instance.showAnnouncement(',
      foregroundStart,
    );
    final foregroundUpdate = fcm.substring(foregroundStart, foregroundEnd);
    expect(foregroundUpdate, isNot(contains("message.data['download_url']")));
    expect(foregroundUpdate, isNot(contains("message.data['url']")));
  });

  test('completed direct update hands off to Android Downloads, not web', () {
    final native = File(
      'android/app/src/main/kotlin/com/otyaplayer/app/UpdateDownloads.kt',
    ).readAsStringSync();
    final dialog =
        File('lib/core/widgets/update_dialog.dart').readAsStringSync();

    expect(native, contains('DownloadManager.ACTION_VIEW_DOWNLOADS'));
    expect(native, contains('private fun openDownloads(tag: String)'));
    expect(native, isNot(contains('canRequestPackageInstalls()')));
    expect(native, isNot(contains('ACTION_MANAGE_UNKNOWN_APP_SOURCES')));
    expect(native, isNot(contains('"install" ->')));
    expect(dialog, contains("'showDownloads',"));
    expect(dialog, contains("? 'Open downloaded update'"));
    expect(dialog, contains('No website is used.'));
    expect(dialog, contains('without opening a website'));
  });

  test('public updater does not request package installer authority', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final config =
        File('scripts/android-release-config.sh').readAsStringSync();

    expect(
      manifest,
      isNot(contains('android.permission.REQUEST_INSTALL_PACKAGES')),
    );
    expect(gradle, isNot(contains('otyaInstallerPermissionNode')));
    expect(gradle, isNot(contains('System.getenv("OTYA_SELF_UPDATE")')));
    expect(config, isNot(contains('export OTYA_SELF_UPDATE=')));
    expect(config, contains(r'SELF_UPDATE=${self_update}'));
  });
}
