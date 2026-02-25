import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/utils/vk_auth.dart';

/// main is the application entry point.

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

  group('parseVkAuthCodeCredentialsFromUri', () {
    test('parses code flow params from query string', () {
      final uri = Uri.parse(
        'https://spacefestival.fun/space_app/auth?code=abc&state=signed.device&device_id=device-1',
      );

      final credentials = parseVkAuthCodeCredentialsFromUri(uri);
      expect(credentials, isNotNull);
      expect(credentials!.code, 'abc');
      expect(credentials.state, 'signed.device');
      expect(credentials.deviceId, 'device-1');
    });

    test('parses code and device when state is missing', () {
      final uri = Uri.parse(
        'https://spacefestival.fun/space_app/auth?code=abc&device_id=device-1',
      );

      final credentials = parseVkAuthCodeCredentialsFromUri(uri);
      expect(credentials, isNotNull);
      expect(credentials!.code, 'abc');
      expect(credentials.state, isEmpty);
      expect(credentials.deviceId, 'device-1');
    });

    test('parses code flow params from payload json', () {
      final payload = Uri.encodeQueryComponent(
        '{"code":"abc","state":"signed.device","device_id":"device-1"}',
      );
      final uri = Uri.parse(
        'https://spacefestival.fun/space_app/auth?payload=$payload',
      );

      final credentials = parseVkAuthCodeCredentialsFromUri(uri);
      expect(credentials, isNotNull);
      expect(credentials!.code, 'abc');
      expect(credentials.state, 'signed.device');
      expect(credentials.deviceId, 'device-1');
    });
  });

  group('parseVkAuthErrorFromUri', () {
    test('parses vk error when state marker is present', () {
      final uri = Uri.parse(
        'https://spacefestival.fun/space_app/auth?error=invalid_request&error_description=redirect_uri+is+incorrect&state=%2Fspace_app',
      );

      final error = parseVkAuthErrorFromUri(uri);
      expect(error, 'invalid_request: redirect_uri is incorrect');
    });
  });
}
