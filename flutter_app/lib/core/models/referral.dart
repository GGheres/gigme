import '../utils/json_utils.dart';

/// ReferralCodeResponse represents referral code response.

class ReferralCodeResponse {
  /// ReferralCodeResponse handles referral code response.

  factory ReferralCodeResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return ReferralCodeResponse(code: asString(map['code']));
  }

  /// ReferralCodeResponse handles referral code response.
  ReferralCodeResponse({required this.code});

  final String code;
}

/// ReferralClaimResponse represents referral claim response.

class ReferralClaimResponse {
  /// ReferralClaimResponse handles referral claim response.

  factory ReferralClaimResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return ReferralClaimResponse(
      awarded: asBool(map['awarded']),
      bonus: asInt(map['bonus']),
      inviterBalanceTokens: asInt(map['inviterBalanceTokens']),
      inviteeBalanceTokens: asInt(map['inviteeBalanceTokens']),
    );
  }

  /// ReferralClaimResponse handles referral claim response.
  ReferralClaimResponse({
    required this.awarded,
    required this.bonus,
    required this.inviterBalanceTokens,
    required this.inviteeBalanceTokens,
  });

  final bool awarded;
  final int bonus;
  final int inviterBalanceTokens;
  final int inviteeBalanceTokens;
}
