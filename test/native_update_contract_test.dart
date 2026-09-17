import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('update notifications never launch a web destination', () {
    final push = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();
    final fcm = File('lib/core/services/fcm_service.dart').readAsStringSync();

    expect(push, contains("static const _nativeUpdatePayload = '\${_prefixUpdate}native';"));
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

  test('completed direct update opens Android package installer', () {
    final native = File(
      'android/app/src/main/kotlin/com/otyaplayer/app/UpdateDownloads.kt',
    ).readAsStringSync();
    final dialog =
        File('lib/core/widgets/update_dialog.dart').readAsStringSync();

    expect(native, contains('"install" ->'));
    expect(native, contains('getUriForDownloadedFile(id)'));
    expect(native, contains('Intent(Intent.ACTION_VIEW)'));
    expect(native, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
    expect(native, contains('canRequestPackageInstalls()'));
    expect(native, contains('Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES'));
    expect(dialog, contains("'install',"));
    expect(dialog, contains("? 'Install update'"));
    expect(dialog, contains('without opening a website'));
  });

  test('installer permission follows SELF_UPDATE channel', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final config =
        File('scripts/android-release-config.sh').readAsStringSync();

    expect(
      manifest,
      contains('android.permission.REQUEST_INSTALL_PACKAGES'),
    );
    expect(manifest, contains('tools:node="\${otyaInstallerPermissionNode}"'));
    expect(gradle, contains('System.getenv("OTYA_SELF_UPDATE")'));
    expect(
      gradle,
      contains('otyaInstallerPermissionNode: otyaSelfUpdateEnabled ? "merge" : "remove"'),
    );
    expect(config, contains('export OTYA_SELF_UPDATE="$self_update"'));
  });
}
