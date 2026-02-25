import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/media_models.dart';
import '../../../core/models/user.dart';
import '../../../core/models/user_event.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/json_utils.dart';

/// UserEventsResponse represents user events response.

class UserEventsResponse {
  /// UserEventsResponse handles user events response.

  factory UserEventsResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return UserEventsResponse(
      items: asList(map['items']).map(UserEvent.fromJson).toList(),
      total: asInt(map['total']),
    );
  }

  /// UserEventsResponse handles user events response.
  UserEventsResponse({
    required this.items,
    required this.total,
  });

  final List<UserEvent> items;
  final int total;
}

/// ProfileRepository represents profile repository.

class ProfileRepository {
  /// ProfileRepository handles profile repository.
  ProfileRepository(this._ref);

  final Ref _ref;

  /// getMe returns me.

  Future<User> getMe({required String token}) {
    return _ref.read(apiClientProvider).get<User>(
          ApiPaths.me,
          token: token,
          retry: false,
          decoder: User.fromJson,
        );
  }

  /// getMyEvents returns my events.

  Future<UserEventsResponse> getMyEvents({
    required String token,
    int limit = 50,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<UserEventsResponse>(
          ApiPaths.eventsMine,
          token: token,
          query: <String, dynamic>{
            'limit': limit,
            'offset': offset,
          },
          decoder: UserEventsResponse.fromJson,
        );
  }

  /// topupToken handles topup token.

  Future<TopupTokenResponse> topupToken({
    required String token,
    required int amount,
  }) {
    return _ref.read(apiClientProvider).post<TopupTokenResponse>(
          ApiPaths.topupToken,
          token: token,
          body: <String, dynamic>{'amount': amount},
          decoder: TopupTokenResponse.fromJson,
        );
  }
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref));
