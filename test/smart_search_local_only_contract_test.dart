import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Smart Search stays local and has no consumer AI fallback', () {
    final search =
        File('lib/features/search/smart_search_sheet.dart').readAsStringSync();

    expect(search.contains('otya_support_service.dart'), isFalse);
    expect(search.contains('OtyaSupportService'), isFalse);
    expect(search.contains('_askAi'), isFalse);
    expect(search.contains("_SectionLabel('Next'"), isFalse);
    expect(search.contains('Optional online help'), isFalse);
    expect(search.contains("'Send files'"), isTrue);
    expect(search.contains('Open Me → Send.'), isTrue);
    expect(search.contains('Search stays local'), isTrue);
    expect(search.contains("'No local matches'"), isTrue);
  });

  test('Privacy copy matches local Search and connected Together boundaries', () {
    final privacy = File(
      'lib/features/settings/presentation/privacy_policy_screen.dart',
    ).readAsStringSync();

    expect(
      privacy.contains('Core playback and Smart Search are offline-first'),
      isTrue,
    );
    expect(
      privacy.contains(
        'An Otya account is optional for local playback, Smart Search',
      ),
      isTrue,
    );
    expect(privacy.contains('and nearby Send. Google Sign-In'), isTrue);
    expect(
      privacy.contains('The Otya Together control plane does not store'),
      isTrue,
    );
    expect(privacy.contains('Messages you send to Next'), isFalse);
    expect(privacy.contains('Transfer sends supported files'), isFalse);
  });

  test('Together end state uses the canonical Otya name', () {
    final together = File(
      'lib/features/together/presentation/nearby_together_live_surface.dart',
    ).readAsStringSync();

    expect(
      together.contains('Your normal Otya playback remains available.'),
      isTrue,
    );
    expect(together.contains('Your normal OTYA playback'), isFalse);
  });
}
