import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release configuration contract', () {
    test('mobile source does not contain server-only secret identifiers', () {
      final roots = <Directory>[
        Directory('lib'),
        Directory('android/app/src/main'),
      ];

      final forbidden = <RegExp>[
        RegExp(r'RESEND_API_KEY'),
        RegExp(r'AUTH_JWT_SECRET'),
        RegExp(r'INTERNAL_SECRET'),
        RegExp(r'TELEGRAM_LOGIN_CLIENT_SECRET'),
        RegExp(r'GOOGLE_CLIENT_SECRET'),
        RegExp(r'SPOTIFY_CLIENT_SECRET'),
        RegExp(r'OPENAI_API_KEY'),
        RegExp(r'GEMINI_API_KEY'),
        RegExp(r'GROQ_API_KEY'),
        RegExp(r'ANTHROPIC_API_KEY'),
        RegExp(r'CF_API_TOKEN'),
        RegExp(r'BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY'),
        RegExp(r'\bsk-[A-Za-z0-9_-]{16,}'),
      ];

      final findings = <String>[];
      for (final root in roots) {
        if (!root.existsSync()) continue;
        for (final entity in root.listSync(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final path = entity.path.replaceAll('\\', '/');
          if (!_isTextSource(path)) continue;
          final text = entity.readAsStringSync();
          for (final pattern in forbidden) {
            if (pattern.hasMatch(text)) {
              findings.add('$path matched ${pattern.pattern}');
            }
          }
        }
      }

      expect(
        findings,
        isEmpty,
        reason: 'Server credentials must never be compiled into the Otya APK.\n'
            '${findings.join('\n')}',
      );
    });

    test('release source has no cleartext or development backend URLs', () {
      final root = Directory('lib');
      final findings = <String>[];
      final forbiddenEverywhere = <RegExp>[
        RegExp(r'\.workers\.dev', caseSensitive: false),
      ];
      final forbiddenHardcodedLoopbackEndpoint = RegExp(
        r'https?://(?:localhost|127\.0\.0\.1)',
        caseSensitive: false,
      );
      final cleartext = RegExp(r'http://', caseSensitive: false);

      if (root.existsSync()) {
        for (final entity in root.listSync(recursive: true, followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final path = entity.path.replaceAll('\\', '/');
          final text = entity.readAsStringSync();

          // Otya Transfer is intentionally local-network only and uses
          // authenticated cleartext HTTP between nearby devices. Together's
          // guest proxy also binds through Dart's IPv4 loopback API and never
          // carries a configurable or remote backend URL. Both protocols have
          // focused URI-policy tests that reject non-local addresses.
          final isLocalPeerTransportSource =
              path.startsWith('lib/features/transfer/') ||
              path ==
                  'lib/features/together/data/together_stream_cache_proxy.dart';
          if (!isLocalPeerTransportSource && cleartext.hasMatch(text)) {
            findings.add('$path matched ${cleartext.pattern}');
          }

          if (forbiddenHardcodedLoopbackEndpoint.hasMatch(text)) {
            findings.add(
              '$path matched ${forbiddenHardcodedLoopbackEndpoint.pattern}',
            );
          }

          for (final pattern in forbiddenEverywhere) {
            if (pattern.hasMatch(text)) {
              findings.add('$path matched ${pattern.pattern}');
            }
          }
        }
      }

      expect(
        findings,
        isEmpty,
        reason: 'Production app source must not contain development or remote '
            'cleartext backend endpoints.\n${findings.join('\n')}',
      );
    });

    test('changeable public values are centralized in Environment', () {
      final env = File('lib/core/config/environment.dart').readAsStringSync();

      expect(env, contains('String.fromEnvironment(\n    \'WORKER_URL\''));
      expect(env, contains('String.fromEnvironment(\n    \'PUBLIC_SITE_URL\''));
      expect(env, contains('String.fromEnvironment(\n    \'SUPPORT_EMAIL\''));
      expect(env, isNot(contains('SPOTIFY_CLIENT_ID')));
      expect(env, isNot(contains('SPOTIFY_REDIRECT_URI')));
      expect(env, isNot(contains('onlineMusicUrl')));
      expect(env, isNot(contains('JAMENDO')));
    });

    test('update notifications use the ABI-specific APK target', () {
      final updateService =
          File('lib/core/services/update_service.dart').readAsStringSync();

      expect(updateService, contains('final abi = _detectAbi();'));
      expect(updateService, contains('downloads[\'arm64\']'));
      expect(updateService, contains('downloads[\'arm32\']'));
      expect(updateService, contains('downloadUrl: directUrl'));
      expect(
        updateService,
        isNot(contains('downloadUrl:\n            downloads[\'auto\']')),
        reason: 'The server legacy auto URL may resolve to arm64. Device update '
            'notifications must use the APK matching the installed app ABI.',
      );
    });

    test('localization generation remains enabled', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final l10n = File('l10n.yaml').readAsStringSync();

      expect(pubspec, contains('generate: true'));
      expect(pubspec, contains('flutter_localizations:'));
      expect(l10n, contains('arb-dir: lib/l10n'));
      expect(File('lib/l10n/app_en.arb').existsSync(), isTrue);
      expect(File('lib/l10n/app_lg.arb').existsSync(), isTrue);
    });
  });
}

bool _isTextSource(String path) {
  return path.endsWith('.dart') ||
      path.endsWith('.xml') ||
      path.endsWith('.gradle') ||
      path.endsWith('.properties') ||
      path.endsWith('.json');
}
