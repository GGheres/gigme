import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/landing_content.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';

class LandingRepository {
  LandingRepository(this._ref);

  final Ref _ref;

  Future<LandingEventsResponse> listEvents({
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

  Future<LandingContent> getContent() {
    return _ref.read(apiClientProvider).get<LandingContent>(
          ApiPaths.landingContent,
          decoder: LandingContent.fromJson,
        );
  }
}

final landingRepositoryProvider = Provider<LandingRepository>((ref) {
  return LandingRepository(ref);
});
