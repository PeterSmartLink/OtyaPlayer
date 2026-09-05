import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Me stays media-first and exposes Send without consumer AI', () {
    final source = File(
      'lib/features/my_space/presentation/my_space_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains("title: 'Send'"));
    expect(source, contains("subtitle: 'Nearby sharing'"));
    expect(source, contains("onTap: () => context.push('/transfer')"));
    expect(source, isNot(contains('_NextCard')));
    expect(source, isNot(contains('OtyaAiMark')));
    expect(source, isNot(contains("title: 'Next'")));
    expect(source, isNot(contains("context.push('/support')")));
  });

  test('Settings contains product settings, not a consumer AI destination', () {
    final source = File(
      'lib/features/settings/presentation/settings_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("const _SectionTitle('Otya')"));
    expect(source, contains("title: 'Check for updates'"));
    expect(source, contains("title: 'Privacy policy'"));
    expect(source, contains("title: 'About Otya'"));
    expect(source, isNot(contains("title: 'Next'")));
    expect(source, isNot(contains("context.push('/support')")));
    expect(source, isNot(contains('Icons.auto_awesome_rounded')));
    expect(source, isNot(contains("'About OTYA'")));
    expect(source, isNot(contains("'OTYA Account'")));
  });

  test('legacy AI links fail soft while main navigation stays one app', () {
    final source = File('lib/app/router.dart').readAsStringSync();

    expect(source, isNot(contains('features/ai/otya_support_screen.dart')));
    expect(
      source,
      contains("GoRoute(path: '/support', redirect: (_, __) => '/about')"),
    );
    expect(
      source,
      contains("GoRoute(path: '/ai', redirect: (_, __) => '/about')"),
    );
    expect(source, contains("static const _routes = ['/', '/music', '/myspace']"));
    expect(source, contains("label: 'Video'"));
    expect(source, contains("label: 'Music'"));
    expect(source, contains("label: 'Me'"));
    expect(source, isNot(contains("label: 'Chat'")));
    expect(source, isNot(contains("label: 'Together'")));
    expect(source, isNot(contains("label: 'Send'")));
  });
}
