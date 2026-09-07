import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('verified Firebase Android identifiers stay pinned', () {
    final firebase = read('lib/core/services/firebase_platform_service.dart');
    final environment = read('lib/core/config/environment.dart');

    expect(firebase, contains('1:82776565585:android:085cf9b4eecb76e9535570'));
    expect(firebase, contains("defaultValue: '82776565585'"));
    expect(firebase, contains("defaultValue: 'otya-player'"));
    expect(environment, contains("appPackageId = 'com.otyaplayer.app'"));
  });

  test('App Check uses debug provider only for debug and Play Integrity otherwise', () {
    final firebase = read('lib/core/services/firebase_platform_service.dart');
    final httpClient = read('lib/core/services/http_client.dart');

    expect(
      firebase,
      contains('kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity'),
    );
    expect(httpClient, contains("request.headers['X-Firebase-AppCheck']"));
  });

  test('App Check tokens are pinned to the configured Otya worker origin', () {
    final httpClient = read('lib/core/services/http_client.dart');

    expect(httpClient, contains("import '../config/environment.dart';"));
    expect(httpClient, contains('Uri.tryParse(Environment.workerUrl)'));
    expect(
      httpClient,
      contains('uri.host.toLowerCase() != workerUri.host.toLowerCase()'),
    );
    expect(httpClient, contains('uri.port != workerUri.port'));
  });

  test('Google backend ID tokens use the shared Web OAuth client id', () {
    final google = read('lib/core/services/google_account_service.dart');
    final workflow = read('.github/workflows/test-apk.yml');
    final releaseConfig = read('scripts/android-release-config.sh');

    expect(google, contains("String.fromEnvironment(\n    'GOOGLE_WEB_CLIENT_ID'"));
    expect(google, contains('serverClientId: _webClientId'));
    expect(
      google,
      contains('82776565585-obr8k53b8n6djsggissv8qne81cm3u5u.apps.googleusercontent.com'),
    );
    expect(workflow, contains('source scripts/android-release-config.sh'));
    expect(workflow, contains(r'"${OTYA_RELEASE_DART_DEFINES[@]}"'));
    expect(
      releaseConfig,
      contains('82776565585-obr8k53b8n6djsggissv8qne81cm3u5u.apps.googleusercontent.com'),
    );
    expect(releaseConfig, contains('--dart-define=GOOGLE_WEB_CLIENT_ID='));
  });

  test('Firebase startup remains after runApp and service credentials stay out of app', () {
    final main = read('lib/main.dart');
    final gitignore = read('.gitignore');

    final runAppIndex = main.indexOf('runApp(');
    final bootstrapScheduleIndex =
        main.indexOf('unawaited(_bootstrapAfterFirstFrame(settingsNotifier))');
    final bootstrapFunctionIndex =
        main.indexOf('Future<void> _bootstrapAfterFirstFrame');
    final backgroundIndex = main.indexOf(
      'await _initBackground(savedSettings, databaseReady);',
      bootstrapFunctionIndex,
    );
    final firebaseIndex = main.indexOf(
      'FirebasePlatformService.instance.initOptionalServices',
    );

    expect(runAppIndex, greaterThanOrEqualTo(0));
    expect(bootstrapScheduleIndex, greaterThan(runAppIndex));
    expect(bootstrapFunctionIndex, greaterThan(runAppIndex));
    expect(backgroundIndex, greaterThan(bootstrapFunctionIndex));
    expect(firebaseIndex, greaterThan(backgroundIndex));

    expect(gitignore, contains('*firebase-adminsdk*.json'));
    expect(gitignore, contains('service-account*.json'));
    expect(gitignore, contains('google-services.json'));
  });
}
