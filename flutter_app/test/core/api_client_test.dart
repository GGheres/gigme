import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/error/app_exception.dart';
import 'package:gigme_flutter/core/network/api_client.dart';
import 'package:gigme_flutter/core/utils/json_utils.dart';

void main() {
  group('ApiClient', () {
    test('retries GET on 5xx and succeeds', () async {
      final adapter = SequenceAdapter(
        responses: {
          'GET /health': [
            const MockResponse(statusCode: 500, body: {'error': 'temporary'}),
            const MockResponse(statusCode: 200, body: {'ok': true}),
          ],
        },
      );

      final dio = Dio(BaseOptions(baseUrl: 'https://gigme.test'));
      dio.httpClientAdapter = adapter;
      final client = ApiClient(baseUrl: 'https://gigme.test', dio: dio);

      final result = await client.get<bool>(
        '/health',
        decoder: (data) => asMap(data)['ok'] == true,
      );

      expect(result, true);
      expect(adapter.callsFor('GET /health'), 2);
    });

    test('does not retry POST', () async {
      final adapter = SequenceAdapter(
        responses: {
          'POST /events': [
            const MockResponse(statusCode: 500, body: {'error': 'db error'}),
          ],
        },
      );

      final dio = Dio(BaseOptions(baseUrl: 'https://gigme.test'));
      dio.httpClientAdapter = adapter;
      final client = ApiClient(baseUrl: 'https://gigme.test', dio: dio);

      expect(
        () => client.post<void>(
          '/events',
          body: {'title': 'test'},
          decoder: (_) {},
        ),
        throwsA(
          isA<AppException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
      expect(adapter.callsFor('POST /events'), 1);
    });
  });
}

class MockResponse {
  const MockResponse({required this.statusCode, required this.body});

  final int statusCode;
  final dynamic body;
}

class SequenceAdapter implements HttpClientAdapter {
  SequenceAdapter({required Map<String, List<MockResponse>> responses}) : _responses = responses;

  final Map<String, List<MockResponse>> _responses;
  final Map<String, int> _calls = <String, int>{};

  int callsFor(String key) => _calls[key] ?? 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method.toUpperCase()} ${options.path}';
    _calls[key] = (_calls[key] ?? 0) + 1;

    final queue = _responses[key];
    if (queue == null || queue.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'unhandled route: $key'}),
        404,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }

    final next = queue.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(next.body),
      next.statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
