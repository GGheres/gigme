import '../utils/json_utils.dart';

class EventComment {
  EventComment({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int eventId;
  final int userId;
  final String userName;
  final String body;
  final DateTime? createdAt;

  factory EventComment.fromJson(dynamic json) {
    final map = asMap(json);
    return EventComment(
      id: asInt(map['id']),
      eventId: asInt(map['eventId']),
      userId: asInt(map['userId']),
      userName: asString(map['userName']),
      body: asString(map['body']),
      createdAt: asDateTime(map['createdAt']),
    );
  }
}
