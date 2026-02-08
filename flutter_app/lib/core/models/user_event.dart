import '../utils/json_utils.dart';

class UserEvent {
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
}
