import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/auth_session.dart';
import '../../../core/models/referral.dart';
import '../../../core/models/user.dart';
import '../../../core/network/api_paths.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/json_utils.dart';

/// VkAuthStartResponse represents vk auth start response.

class VkAuthStartResponse {
  /// VkAuthStartResponse handles vk auth start response.
  VkAuthStartResponse({
    required this.authorizeUrl,
  });

  /// VkAuthStartResponse handles vk auth start response.

  factory VkAuthStartResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return VkAuthStartResponse(
      authorizeUrl: asString(map['authorizeUrl']),
    );
  }

  final String authorizeUrl;
}

/// AuthRepository represents auth repository.

class AuthRepository {
  /// AuthRepository authenticates repository.
  AuthRepository(this._ref);

  final Ref _ref;

  /// loginWithTelegram handles login with telegram.

  Future<AuthSession> loginWithTelegram(String initData) {
    return _ref.read(apiClientProvider).post<AuthSession>(
          ApiPaths.authTelegram,
          body: <String, dynamic>{'initData': initData},
          decoder: AuthSession.fromJson,
        );
  }

  /// loginWithVk handles login with vk.

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

  /// loginWithVkCode handles login with vk code.

  Future<AuthSession> loginWithVkCode({
    required String code,
    required String state,
    required String deviceId,
  }) {
    return _ref.read(apiClientProvider).post<AuthSession>(
          ApiPaths.authVk,
          body: <String, dynamic>{
            'code': code,
            'state': state,
            'deviceId': deviceId,
          },
          decoder: AuthSession.fromJson,
        );
  }

  /// startVkAuth handles start vk auth.

  Future<Uri> startVkAuth({
    required String redirectUri,
    String? next,
  }) async {
    final response =
        await _ref.read(apiClientProvider).post<VkAuthStartResponse>(
              ApiPaths.authVkStart,
              body: <String, dynamic>{
                'redirectUri': redirectUri,
                if (next != null && next.trim().isNotEmpty) 'next': next.trim(),
              },
              decoder: VkAuthStartResponse.fromJson,
            );

    final uri = Uri.tryParse(response.authorizeUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('Backend returned invalid VK authorize URL');
    }
    return uri;
  }

  /// loginWithVkMiniApp handles login with vk mini app.

  Future<AuthSession> loginWithVkMiniApp({
    required String launchParams,
  }) {
    return _ref.read(apiClientProvider).post<AuthSession>(
          ApiPaths.authVkMiniApp,
          body: <String, dynamic>{'launchParams': launchParams},
          decoder: AuthSession.fromJson,
        );
  }

  /// getMe returns me.

  Future<User> getMe(String token) {
    return _ref.read(apiClientProvider).get<User>(
          ApiPaths.me,
          token: token,
          retry: false,
          decoder: User.fromJson,
        );
  }

  /// claimReferral claims referral.

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

    /// AuthRepository authenticates repository.
    Provider<AuthRepository>((ref) => AuthRepository(ref));
