import '../utils/json_utils.dart';

/// User represents user.

class User {
  /// User handles internal user behavior.
  factory User.fromJson(dynamic json) {
    final map = asMap(json);
    return User(
      id: asInt(map['id']),
      telegramId: asInt(map['telegramId']),
      firstName: asString(map['firstName']),
      lastName: asString(map['lastName']),
      username: asString(map['username']),
      photoUrl: asString(map['photoUrl']),
      rating: asDouble(map['rating']),
      ratingCount: asInt(map['ratingCount']),
      balanceTokens: asInt(map['balanceTokens']),
    );
  }

  /// User handles internal user behavior.
  User({
    required this.id,
    required this.telegramId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.photoUrl,
    required this.rating,
    required this.ratingCount,
    required this.balanceTokens,
  });

  final int id;
  final int telegramId;
  final String firstName;
  final String lastName;
  final String username;
  final String photoUrl;
  final double rating;
  final int ratingCount;
  final int balanceTokens;

  /// toJson handles to json.

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'telegramId': telegramId,
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'photoUrl': photoUrl,
      'rating': rating,
      'ratingCount': ratingCount,
      'balanceTokens': balanceTokens,
    };
  }

  /// displayName handles display name.

  String get displayName {
    final full = [firstName, lastName]
        .where((e) => e.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (full.isNotEmpty) return full;
    if (username.trim().isNotEmpty) return '@${username.trim()}';
    return 'User';
  }

  /// handle handles the requested data.

  String get handle => username.trim().isEmpty ? '' : '@${username.trim()}';

  /// copyWith handles copy with.

  User copyWith({
    int? id,
    int? telegramId,
    String? firstName,
    String? lastName,
    String? username,
    String? photoUrl,
    double? rating,
    int? ratingCount,
    int? balanceTokens,
  }) {
    return User(
      id: id ?? this.id,
      telegramId: telegramId ?? this.telegramId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      balanceTokens: balanceTokens ?? this.balanceTokens,
    );
  }
}
