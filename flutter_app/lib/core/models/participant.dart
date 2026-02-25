import '../utils/json_utils.dart';

/// Participant represents participant.

class Participant {
  /// Participant handles internal participant behavior.

  factory Participant.fromJson(dynamic json) {
    final map = asMap(json);
    return Participant(
      userId: asInt(map['userId']),
      name: asString(map['name']),
      joinedAt: asDateTime(map['joinedAt']),
    );
  }

  /// Participant handles internal participant behavior.
  Participant({
    required this.userId,
    required this.name,
    required this.joinedAt,
  });

  final int userId;
  final String name;
  final DateTime? joinedAt;
}
