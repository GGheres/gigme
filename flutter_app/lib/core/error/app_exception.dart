class AppException implements Exception {
  AppException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isServerError => (statusCode ?? 0) >= 500;

  @override
  String toString() => 'AppException(status=$statusCode, message=$message)';
}
