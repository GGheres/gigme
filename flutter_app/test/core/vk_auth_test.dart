import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/utils/vk_auth.dart';

void main() {
  group('extractVkMiniAppLaunchParams', () {
    test('returns raw query when vk launch params are present', () {
      final uri = Uri.parse(
        'https://spacefestival.fun/space_app/auth?vk_app_id=1&vk_user_id=2&vk_platform=desktop_web&sign=abc',
      );

      final raw = extractVkMiniAppLaunchParams(uri);
      expect(raw, isNotNull);
      expect(raw, contains('vk_app_id=1'));
      expect(raw, contains('vk_user_id=2'));
      expect(raw, contains('sign=abc'));
    });

    test('returns null when required params are missing', () {
      final uri = Uri.parse(
        'https://spacefestival.fun/space_app/auth?vk_app_id=1&vk_user_id=2',
      );

      final raw = extractVkMiniAppLaunchParams(uri);
      expect(raw, isNull);
    });
  });
}
