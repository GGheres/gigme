import '../utils/json_utils.dart';
import 'user.dart';

/// AuthSession represents auth session.

class AuthSession {
  /// AuthSession authenticates session.

  factory AuthSession.fromJson(dynamic json) {
    final map = asMap(json);
    return AuthSession(
      accessToken: asString(map['accessToken']),
      user: User.fromJson(map['user']),
      isNew: asBool(map['isNew']),
    );
  }

  /// AuthSession authenticates session.
  AuthSession({
    required this.accessToken,
    required this.user,
    required this.isNew,
  });

  final String accessToken;
  final User user;
  final bool isNew;
}
