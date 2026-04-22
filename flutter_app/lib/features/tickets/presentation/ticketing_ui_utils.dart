import 'package:flutter/material.dart';

import 'order_status.dart';

/// Formats money amount in cents to a human-readable currency string.
String formatMoney(int cents, {String currency = 'RUB'}) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final units = absolute ~/ 100;
  final fraction = absolute % 100;
  final value = '$units.${fraction.toString().padLeft(2, '0')}';
  return negative ? '-$value $currency' : '$value $currency';
}

/// Foreground color for an order status code.
///
/// Delegates to [OrderStatusPalette] so there's one source of truth.
Color statusColor(String status, BuildContext context) {
  return OrderStatusPalette.of(OrderStatus.fromCode(status), context)
      .foreground;
}

/// Tinted background for an order status code.
///
/// Delegates to [OrderStatusPalette] so there's one source of truth.
Color statusTint(String status, BuildContext context) {
  return OrderStatusPalette.of(OrderStatus.fromCode(status), context).tint;
}

/// buildBotReplyDeepLink builds a Telegram deep link for the admin-to-user
/// reply flow.
String buildBotReplyDeepLink({
  required String botUsername,
  required int telegramId,
}) {
  if (telegramId <= 0) return '';
  final username = botUsername.trim().replaceFirst(RegExp(r'^@'), '').trim();
  if (username.isEmpty) return '';
  return 'https://t.me/$username?start=reply_$telegramId';
}
