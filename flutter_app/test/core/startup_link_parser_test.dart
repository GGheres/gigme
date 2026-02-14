import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/utils/startup_link.dart';

void main() {
  group('StartupLinkParser', () {
    test('parses startapp query with private event key and referral code', () {
      final uri = Uri.parse(
        'https://gigme.test/?startapp=e_9_3nZuBc6dFH5rwM_cgwpBCA__r_LKCU5ZBQ',
      );

      final parsed = StartupLinkParser.parseFromUriForTesting(uri);

      expect(parsed.eventId, 9);
      expect(parsed.eventKey, '3nZuBc6dFH5rwM_cgwpBCA');
      expect(parsed.refCode, 'LKCU5ZBQ');
    });

    test('parses tgWebAppStartParam from fragment params', () {
      final uri =
          Uri.parse('https://gigme.test/#tgWebAppStartParam=e_17_myKey__r_r1');

      final parsed = StartupLinkParser.parseFromUriForTesting(uri);

      expect(parsed.eventId, 17);
      expect(parsed.eventKey, 'myKey');
      expect(parsed.refCode, 'r1');
    });

    test('parses start_param from tgWebAppData payload', () {
      final uri = Uri.parse(
        'https://gigme.test/#tgWebAppData=start_param%3De_42_secret__r_code123',
      );

      final parsed = StartupLinkParser.parseFromUriForTesting(uri);

      expect(parsed.eventId, 42);
      expect(parsed.eventKey, 'secret');
      expect(parsed.refCode, 'code123');
    });

    test('supports canonical format without event key', () {
      final parsed = StartupLinkParser.parseStartParamForTesting('e_33__r_ref');

      expect(parsed.eventId, 33);
      expect(parsed.eventKey, isNull);
      expect(parsed.refCode, 'ref');
    });
  });
}
