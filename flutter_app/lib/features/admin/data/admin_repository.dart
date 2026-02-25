import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/admin_models.dart';
import '../../../core/models/landing_content.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/json_utils.dart';

/// AdminRepository represents admin repository.

class AdminRepository {
  /// AdminRepository handles admin repository.
  AdminRepository(this._ref);

  final Ref _ref;

  /// login handles internal login behavior.

  Future<AdminLoginResponse> login({
    required String username,
    required String password,
    int? telegramId,
  }) {
    return _ref.read(apiClientProvider).post<AdminLoginResponse>(
          '/auth/admin',
          body: <String, dynamic>{
            'username': username,
            'password': password,
            if (telegramId != null && telegramId > 0) 'telegramId': telegramId,
          },
          decoder: AdminLoginResponse.fromJson,
        );
  }

  /// listUsers lists users.

  Future<AdminUsersResponse> listUsers({
    required String token,
    String? search,
    String? blocked,
    int limit = 50,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<AdminUsersResponse>(
          '/admin/users',
          token: token,
          query: <String, dynamic>{
            if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
            if ((blocked ?? '').trim().isNotEmpty) 'blocked': blocked!.trim(),
            'limit': limit,
            'offset': offset,
          },
          decoder: AdminUsersResponse.fromJson,
        );
  }

  /// getUser returns user.

  Future<AdminUserDetailResponse> getUser({
    required String token,
    required int id,
  }) {
    return _ref.read(apiClientProvider).get<AdminUserDetailResponse>(
          '/admin/users/$id',
          token: token,
          decoder: AdminUserDetailResponse.fromJson,
          retry: false,
        );
  }

  /// blockUser handles block user.

  Future<void> blockUser({
    required String token,
    required int id,
    required String reason,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          '/admin/users/$id/block',
          token: token,
          body: <String, dynamic>{
            'reason': reason,
          },
          decoder: (_) {},
        );
  }

  /// unblockUser handles unblock user.

  Future<void> unblockUser({
    required String token,
    required int id,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          '/admin/users/$id/unblock',
          token: token,
          body: const <String, dynamic>{},
          decoder: (_) {},
        );
  }

  /// listBroadcasts lists broadcasts.

  Future<AdminBroadcastsResponse> listBroadcasts({
    required String token,
    int limit = 50,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<AdminBroadcastsResponse>(
          '/admin/broadcasts',
          token: token,
          query: <String, dynamic>{
            'limit': limit,
            'offset': offset,
          },
          decoder: AdminBroadcastsResponse.fromJson,
        );
  }

  /// createBroadcast creates broadcast.

  Future<AdminCreateBroadcastResponse> createBroadcast({
    required String token,
    required String audience,
    required String message,
    List<int>? userIds,
    Map<String, dynamic>? filters,
    List<BroadcastButton>? buttons,
  }) {
    return _ref.read(apiClientProvider).post<AdminCreateBroadcastResponse>(
          '/admin/broadcasts',
          token: token,
          body: <String, dynamic>{
            'audience': audience,
            'message': message,
            if ((userIds ?? const <int>[]).isNotEmpty) 'userIds': userIds,
            if ((filters ?? const <String, dynamic>{}).isNotEmpty)
              'filters': filters,
            if ((buttons ?? const <BroadcastButton>[]).isNotEmpty)
              'buttons': buttons!.map((button) => button.toJson()).toList(),
          },
          decoder: AdminCreateBroadcastResponse.fromJson,
        );
  }

  /// startBroadcast handles start broadcast.

  Future<void> startBroadcast({
    required String token,
    required int id,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          '/admin/broadcasts/$id/start',
          token: token,
          body: const <String, dynamic>{},
          decoder: (_) {},
        );
  }

  /// listParserSources lists parser sources.

  Future<AdminParserSourcesResponse> listParserSources({
    required String token,
    int limit = 100,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<AdminParserSourcesResponse>(
          '/admin/parser/sources',
          token: token,
          query: <String, dynamic>{
            'limit': limit,
            'offset': offset,
          },
          decoder: AdminParserSourcesResponse.fromJson,
        );
  }

  /// createParserSource creates parser source.

  Future<AdminParserSource> createParserSource({
    required String token,
    required String sourceType,
    required String input,
    String? title,
    bool isActive = true,
  }) {
    return _ref.read(apiClientProvider).post<AdminParserSource>(
          '/admin/parser/sources',
          token: token,
          body: <String, dynamic>{
            'sourceType': sourceType,
            'input': input,
            if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
            'isActive': isActive,
          },
          decoder: AdminParserSource.fromJson,
        );
  }

  /// updateParserSource updates parser source.

  Future<void> updateParserSource({
    required String token,
    required int id,
    required bool isActive,
  }) {
    return _ref.read(apiClientProvider).patch<void>(
          '/admin/parser/sources/$id',
          token: token,
          body: <String, dynamic>{'isActive': isActive},
          decoder: (_) {},
        );
  }

  /// parseSource parses source.

  Future<AdminParserParseResponse> parseSource({
    required String token,
    required int id,
  }) {
    return _ref.read(apiClientProvider).post<AdminParserParseResponse>(
          '/admin/parser/sources/$id/parse',
          token: token,
          body: const <String, dynamic>{},
          decoder: AdminParserParseResponse.fromJson,
        );
  }

  /// parseInput parses input.

  Future<AdminParserParseResponse> parseInput({
    required String token,
    required String sourceType,
    required String input,
  }) {
    return _ref.read(apiClientProvider).post<AdminParserParseResponse>(
          '/admin/parser/parse',
          token: token,
          body: <String, dynamic>{
            'sourceType': sourceType,
            'input': input,
          },
          decoder: AdminParserParseResponse.fromJson,
        );
  }

  /// listParsedEvents lists parsed events.

  Future<AdminParsedEventsResponse> listParsedEvents({
    required String token,
    String? status,
    int? sourceId,
    int limit = 100,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<AdminParsedEventsResponse>(
          '/admin/parser/events',
          token: token,
          query: <String, dynamic>{
            if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
            if (sourceId != null && sourceId > 0) 'sourceId': sourceId,
            'limit': limit,
            'offset': offset,
          },
          decoder: AdminParsedEventsResponse.fromJson,
        );
  }

  /// geocode handles internal geocode behavior.

  Future<GeocodeResultsResponse> geocode({
    required String token,
    required String query,
    int limit = 1,
  }) {
    return _ref.read(apiClientProvider).post<GeocodeResultsResponse>(
          '/admin/parser/geocode',
          token: token,
          body: <String, dynamic>{
            'query': query,
            'limit': limit,
          },
          decoder: GeocodeResultsResponse.fromJson,
        );
  }

  /// importParsedEvent imports parsed event.

  Future<int> importParsedEvent({
    required String token,
    required int id,
    String? title,
    String? description,
    String? startsAt,
    required double lat,
    required double lng,
    String? addressLabel,
    List<String>? media,
    List<String>? links,
    List<String>? filters,
  }) {
    return _ref.read(apiClientProvider).post<int>(
      '/admin/parser/events/$id/import',
      token: token,
      body: <String, dynamic>{
        if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
        if ((description ?? '').trim().isNotEmpty)
          'description': description!.trim(),
        if ((startsAt ?? '').trim().isNotEmpty) 'startsAt': startsAt!.trim(),
        'lat': lat,
        'lng': lng,
        if ((addressLabel ?? '').trim().isNotEmpty)
          'addressLabel': addressLabel!.trim(),
        if ((media ?? const <String>[]).isNotEmpty) 'media': media,
        if ((links ?? const <String>[]).isNotEmpty) 'links': links,
        if ((filters ?? const <String>[]).isNotEmpty) 'filters': filters,
      },
      decoder: (data) {
        final map = asMap(data);
        return asInt(map['eventId']);
      },
    );
  }

  /// rejectParsedEvent rejects parsed event.

  Future<void> rejectParsedEvent({
    required String token,
    required int id,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          '/admin/parser/events/$id/reject',
          token: token,
          body: const <String, dynamic>{},
          decoder: (_) {},
        );
  }

  /// deleteParsedEvent deletes parsed event.

  Future<void> deleteParsedEvent({
    required String token,
    required int id,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          '/admin/parser/events/$id',
          token: token,
          decoder: (_) {},
        );
  }

  /// listLandingEvents lists landing events.

  Future<LandingEventsResponse> listLandingEvents({
    int limit = 100,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<LandingEventsResponse>(
          ApiPaths.landingEvents,
          query: <String, dynamic>{
            'limit': limit,
            'offset': offset,
          },
          decoder: LandingEventsResponse.fromJson,
        );
  }

  /// setLandingPublished sets landing published.

  Future<void> setLandingPublished({
    required String token,
    required int eventId,
    required bool published,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.adminLandingPublish(eventId),
          token: token,
          body: <String, dynamic>{'published': published},
          decoder: (_) {},
        );
  }

  /// getEventMedia returns event media.

  Future<List<String>> getEventMedia({
    required String token,
    required int eventId,
  }) {
    return _ref.read(apiClientProvider).get<List<String>>(
      ApiPaths.eventById(eventId),
      token: token,
      decoder: (data) {
        final map = asMap(data);
        return asList(map['media'])
            .map((item) => asString(item).trim())
            .where((item) => item.isNotEmpty)
            .toList();
      },
      retry: false,
    );
  }

  /// updateEventMedia updates event media.

  Future<void> updateEventMedia({
    required String token,
    required int eventId,
    required List<String> media,
  }) {
    return _ref.read(apiClientProvider).patch<void>(
          ApiPaths.adminEventById(eventId),
          token: token,
          body: <String, dynamic>{'media': media},
          decoder: (_) {},
        );
  }

  /// deleteEvent deletes event.

  Future<void> deleteEvent({
    required String token,
    required int eventId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          ApiPaths.adminEventById(eventId),
          token: token,
          decoder: (_) {},
        );
  }

  /// deleteComment deletes comment.

  Future<void> deleteComment({
    required String token,
    required int commentId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          ApiPaths.adminCommentById(commentId),
          token: token,
          decoder: (_) {},
        );
  }

  /// getLandingContent returns landing content.

  Future<LandingContent> getLandingContent() {
    return _ref.read(apiClientProvider).get<LandingContent>(
          ApiPaths.landingContent,
          decoder: LandingContent.fromJson,
        );
  }

  /// updateLandingContent updates landing content.

  Future<void> updateLandingContent({
    required String token,
    required LandingContent content,
  }) {
    return _ref.read(apiClientProvider).post<void>(
          ApiPaths.adminLandingContent,
          token: token,
          body: content.toJson(),
          decoder: (_) {},
        );
  }
}

final adminRepositoryProvider =

    /// AdminRepository handles admin repository.
    Provider<AdminRepository>((ref) => AdminRepository(ref));
