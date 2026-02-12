import '../utils/json_utils.dart';
import 'user.dart';

class AuthSession {

  factory AuthSession.fromJson(dynamic json) {
    final map = asMap(json);
    return AuthSession(
      accessToken: asString(map['accessToken']),
      user: User.fromJson(map['user']),
      isNew: asBool(map['isNew']),
    );
  }
  AuthSession({
    required this.accessToken,
    required this.user,
    required this.isNew,
  });

  final String accessToken;
  final User user;
  final bool isNew;
}
