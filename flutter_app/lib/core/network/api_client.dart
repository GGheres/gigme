import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../error/app_exception.dart';

typedef JsonDecoder<T> = T Function(dynamic data);

/// ApiClient represents api client.

class ApiClient {
  /// ApiClient handles api client.
  ApiClient({required String baseUrl, Dio? dio})
      : _dio = dio ??

            /// Dio handles internal dio behavior.
            Dio(
              /// BaseOptions handles base options.
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 8),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'Content-Type': 'application/json',
                },
              ),
            );

  final Dio _dio;

  /// T handles internal t behavior.

  Future<T> get<T>(
    String path, {
    required JsonDecoder<T> decoder,
    Map<String, dynamic>? query,
    String? token,
    bool retry = true,
  }) async {
    final response = await _requestWithRetry(
      method: 'GET',
      path: path,
      query: query,
      token: token,
      attempts: retry ? 3 : 1,
    );
    return decoder(response.data);
  }

  /// T handles internal t behavior.

  Future<T> post<T>(
    String path, {
    required JsonDecoder<T> decoder,
    dynamic body,
    Map<String, dynamic>? query,
    String? token,
  }) async {
    final response = await _requestWithRetry(
      method: 'POST',
      path: path,
      body: body,
      query: query,
      token: token,
      attempts: 1,
    );
    return decoder(response.data);
  }

  /// T handles internal t behavior.

  Future<T> patch<T>(
    String path, {
    required JsonDecoder<T> decoder,
    dynamic body,
    Map<String, dynamic>? query,
    String? token,
  }) async {
    final response = await _requestWithRetry(
      method: 'PATCH',
      path: path,
      body: body,
      query: query,
      token: token,
      attempts: 1,
    );
    return decoder(response.data);
  }

  /// T handles internal t behavior.

  Future<T> delete<T>(
    String path, {
    required JsonDecoder<T> decoder,
    dynamic body,
    Map<String, dynamic>? query,
    String? token,
  }) async {
    final response = await _requestWithRetry(
      method: 'DELETE',
      path: path,
      body: body,
      query: query,
      token: token,
      attempts: 1,
    );
    return decoder(response.data);
  }

  /// putBytes handles put bytes.

  Future<void> putBytes(
    String url, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _dio.putUri<void>(
        Uri.parse(url),
        data: bytes,
        options: Options(
          headers: {
            'Content-Type': contentType,
          },
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (error) {
      throw _toException(error);
    }
  }

  /// T handles internal t behavior.

  Future<T> postMultipart<T>(
    String path, {
    required JsonDecoder<T> decoder,
    required String fileFieldName,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    String? token,
    Map<String, dynamic> fields = const <String, dynamic>{},
  }) async {
    final formData = FormData.fromMap(
      Map<String, dynamic>.from(fields)
        ..[fileFieldName] = MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
    );

    try {
      final response = await _dio.post<dynamic>(
        path,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          headers: {
            if (token != null && token.trim().isNotEmpty)
              'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );
      return decoder(response.data);
    } on DioException catch (error) {
      throw _toException(error);
    }
  }

  /// _requestWithRetry handles request with retry.

  Future<Response<dynamic>> _requestWithRetry({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    dynamic body,
    String? token,
    required int attempts,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await _dio.request<dynamic>(
          path,
          queryParameters: query,
          data: body,
          options: Options(
            method: method,
            headers: {
              if (token != null && token.trim().isNotEmpty)
                'Authorization': 'Bearer ${token.trim()}',
            },
          ),
        );
      } on DioException catch (error) {
        final shouldRetry = method.toUpperCase() == 'GET' &&
            attempt < attempts &&
            _isRetryable(error);
        if (shouldRetry) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
          continue;
        }
        throw _toException(error);
      }
    }
  }

  /// _isRetryable reports whether retryable condition is met.

  bool _isRetryable(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }

    final status = error.response?.statusCode ?? 0;
    return status == 429 || status >= 500;
  }

  /// _toException handles to exception.

  AppException _toException(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    var message = 'Request failed';
    if (data is Map && data['error'] is String) {
      message = data['error'] as String;
    } else if (data is String && data.trim().isNotEmpty) {
      message = data.trim();
    } else if (error.message != null && error.message!.trim().isNotEmpty) {
      message = error.message!.trim();
    }

    return AppException(
      message,
      statusCode: status,
      code: error.type.name,
    );
  }
}
