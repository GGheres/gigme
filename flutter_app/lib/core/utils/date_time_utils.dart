import 'dart:math' as math;

import 'package:intl/intl.dart';

String formatDateTime(DateTime? value) {
  if (value == null) return '—';
  final localValue = value.toLocal();
  try {
    return DateFormat('dd MMM yyyy, HH:mm', 'ru_RU').format(localValue);
  } catch (_) {
    return DateFormat('dd MMM yyyy, HH:mm').format(localValue);
  }
}

String formatDistanceKm(double distanceKm) {
  if (distanceKm <= 0) return '0 km';
  if (distanceKm < 1) {
    return '${(distanceKm * 1000).round()} m';
  }
  return '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km';
}

double haversineKm({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          (math.sin(dLng / 2) * math.sin(dLng / 2));
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double value) => value * (3.141592653589793 / 180.0);
