/// asMap handles as map.
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, dynamic val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

/// asList handles as list.

List<dynamic> asList(dynamic value) {
  if (value is List) return value;
  return <dynamic>[];
}

/// asString handles as string.

String asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

/// asInt handles as int.

int asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// asDouble handles as double.

double asDouble(dynamic value, {double fallback = 0.0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// asBool handles as bool.

bool asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  if (value is num) return value != 0;
  return fallback;
}

/// asDateTime handles as date time.

DateTime? asDateTime(dynamic value) {
  final raw = asString(value);
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
