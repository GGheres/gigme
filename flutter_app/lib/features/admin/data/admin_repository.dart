import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/admin_models.dart';
import '../../../core/models/landing_content.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/json_utils.dart';

class AdminRepository {
  AdminRepository(this._ref);

  final Ref _ref;

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

  Future<LandingContent> getLandingContent() {
    return _ref.read(apiClientProvider).get<LandingContent>(
          ApiPaths.landingContent,
          decoder: LandingContent.fromJson,
        );
  }

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
    Provider<AdminRepository>((ref) => AdminRepository(ref));
