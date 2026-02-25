/// AppException represents app exception.
class AppException implements Exception {
  /// AppException handles app exception.
  AppException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  /// isUnauthorized reports whether unauthorized condition is met.

  bool get isUnauthorized => statusCode == 401;

  /// isForbidden reports whether forbidden condition is met.
  bool get isForbidden => statusCode == 403;

  /// isServerError reports whether server error condition is met.
  bool get isServerError => (statusCode ?? 0) >= 500;

  /// toString handles to string.

  @override
  String toString() => 'AppException(status=$statusCode, message=$message)';
}
