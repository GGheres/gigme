import '../utils/json_utils.dart';

class PresignResponse {
  PresignResponse({
    required this.uploadUrl,
    required this.fileUrl,
  });

  final String uploadUrl;
  final String fileUrl;

  factory PresignResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return PresignResponse(
      uploadUrl: asString(map['uploadUrl']),
      fileUrl: asString(map['fileUrl']),
    );
  }
}

class CreateEventResponse {
  CreateEventResponse({
    required this.eventId,
    required this.accessKey,
  });

  final int eventId;
  final String accessKey;

  factory CreateEventResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return CreateEventResponse(
      eventId: asInt(map['eventId']),
      accessKey: asString(map['accessKey']),
    );
  }
}

class TopupTokenResponse {
  TopupTokenResponse({required this.balanceTokens});

  final int balanceTokens;

  factory TopupTokenResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return TopupTokenResponse(balanceTokens: asInt(map['balanceTokens']));
  }
}
