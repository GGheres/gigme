import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/auth_session.dart';
import '../../../core/models/referral.dart';
import '../../../core/models/user.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';

class AuthRepository {
  AuthRepository(this._ref);

  final Ref _ref;

  Future<AuthSession> loginWithTelegram(String initData) {
    return _ref.read(apiClientProvider).post<AuthSession>(
          ApiPaths.authTelegram,
          body: <String, dynamic>{'initData': initData},
          decoder: AuthSession.fromJson,
        );
  }

  Future<AuthSession> loginWithVk({
    required String accessToken,
    int? userId,
  }) {
    return _ref.read(apiClientProvider).post<AuthSession>(
          ApiPaths.authVk,
          body: <String, dynamic>{
            'accessToken': accessToken,
            if (userId != null && userId > 0) 'userId': userId,
          },
          decoder: AuthSession.fromJson,
        );
  }

  Future<User> getMe(String token) {
    return _ref.read(apiClientProvider).get<User>(
          ApiPaths.me,
          token: token,
          retry: false,
          decoder: User.fromJson,
        );
  }

  Future<ReferralClaimResponse> claimReferral({
    required String token,
    required int eventId,
    required String refCode,
  }) {
    return _ref.read(apiClientProvider).post<ReferralClaimResponse>(
          ApiPaths.referralClaim,
          token: token,
          body: <String, dynamic>{
            'eventId': eventId,
            'refCode': refCode,
          },
          decoder: ReferralClaimResponse.fromJson,
        );
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref));
