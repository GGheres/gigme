import '../utils/json_utils.dart';

/// UserEvent represents user event.

class UserEvent {
  /// UserEvent handles user event.

  factory UserEvent.fromJson(dynamic json) {
    final map = asMap(json);
    return UserEvent(
      id: asInt(map['id']),
      title: asString(map['title']),
      startsAt: asDateTime(map['startsAt']),
      participantsCount: asInt(map['participantsCount']),
      thumbnailUrl: asString(map['thumbnailUrl']),
    );
  }

  /// UserEvent handles user event.
  UserEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.participantsCount,
    required this.thumbnailUrl,
  });

  final int id;
  final String title;
  final DateTime? startsAt;
  final int participantsCount;
  final String thumbnailUrl;
}
