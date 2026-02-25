import '../utils/json_utils.dart';

/// PresignResponse represents presign response.

class PresignResponse {
  /// PresignResponse handles presign response.

  factory PresignResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return PresignResponse(
      uploadUrl: asString(map['uploadUrl']),
      fileUrl: asString(map['fileUrl']),
    );
  }

  /// PresignResponse handles presign response.
  PresignResponse({
    required this.uploadUrl,
    required this.fileUrl,
  });

  final String uploadUrl;
  final String fileUrl;
}

/// CreateEventResponse represents create event response.

class CreateEventResponse {
  /// CreateEventResponse creates event response.

  factory CreateEventResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return CreateEventResponse(
      eventId: asInt(map['eventId']),
      accessKey: asString(map['accessKey']),
    );
  }

  /// CreateEventResponse creates event response.
  CreateEventResponse({
    required this.eventId,
    required this.accessKey,
  });

  final int eventId;
  final String accessKey;
}

/// TopupTokenResponse represents topup token response.

class TopupTokenResponse {
  /// TopupTokenResponse handles topup token response.

  factory TopupTokenResponse.fromJson(dynamic json) {
    final map = asMap(json);
    return TopupTokenResponse(balanceTokens: asInt(map['balanceTokens']));
  }

  /// TopupTokenResponse handles topup token response.
  TopupTokenResponse({required this.balanceTokens});

  final int balanceTokens;
}
