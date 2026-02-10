import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/utils/event_media_url_utils.dart';

void main() {
  test('builds proxy media url for absolute api base', () {
    final result = buildEventMediaProxyUrl(
      apiUrl: 'https://spacefestival.fun/api',
      eventId: 42,
      index: 0,
    );

    expect(result, 'https://spacefestival.fun/api/media/events/42/0');
  });

  test('builds proxy media url for relative api base', () {
    final result = buildEventMediaProxyUrl(
      apiUrl: '/api',
      eventId: 7,
      index: 1,
    );

    expect(result, '/api/media/events/7/1');
  });

  test('adds eventKey query for private media access', () {
    final result = buildEventMediaProxyUrl(
      apiUrl: 'https://spacefestival.fun/api',
      eventId: 5,
      index: 2,
      accessKey: 'secret-key',
    );

    expect(
      result,
      'https://spacefestival.fun/api/media/events/5/2?eventKey=secret-key',
    );
  });

  test('returns empty string for invalid event id or index', () {
    expect(
      buildEventMediaProxyUrl(
        apiUrl: 'https://spacefestival.fun/api',
        eventId: 0,
        index: 0,
      ),
      isEmpty,
    );
    expect(
      buildEventMediaProxyUrl(
        apiUrl: 'https://spacefestival.fun/api',
        eventId: 1,
        index: -1,
      ),
      isEmpty,
    );
  });
}
