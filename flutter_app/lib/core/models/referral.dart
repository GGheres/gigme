import '../utils/json_utils.dart';

class ReferralCodeResponse {
  ReferralCodeResponse({required this.code});

  final String code;

  factory ReferralCodeResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return ReferralCodeResponse(code: asString(map['code']));
  }
}

class ReferralClaimResponse {
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

  factory ReferralClaimResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return ReferralClaimResponse(
      awarded: asBool(map['awarded']),
      bonus: asInt(map['bonus']),
      inviterBalanceTokens: asInt(map['inviterBalanceTokens']),
      inviteeBalanceTokens: asInt(map['inviteeBalanceTokens']),
    );
  }
}
