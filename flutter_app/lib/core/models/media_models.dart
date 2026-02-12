import '../utils/json_utils.dart';

class PresignResponse {

  factory PresignResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return PresignResponse(
      uploadUrl: asString(map['uploadUrl']),
      fileUrl: asString(map['fileUrl']),
    );
  }
  PresignResponse({
    required this.uploadUrl,
    required this.fileUrl,
  });

  final String uploadUrl;
  final String fileUrl;
}

class CreateEventResponse {

  factory CreateEventResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return CreateEventResponse(
      eventId: asInt(map['eventId']),
      accessKey: asString(map['accessKey']),
    );
  }
  CreateEventResponse({
    required this.eventId,
    required this.accessKey,
  });

  final int eventId;
  final String accessKey;
}

class TopupTokenResponse {

  factory TopupTokenResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return TopupTokenResponse(balanceTokens: asInt(map['balanceTokens']));
  }
  TopupTokenResponse({required this.balanceTokens});

  final int balanceTokens;
}
