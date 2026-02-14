import 'package:flutter/material.dart';

String formatMoney(int cents, {String currency = 'RUB'}) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final units = absolute ~/ 100;
  final fraction = absolute % 100;
  final value = '$units.${fraction.toString().padLeft(2, '0')}';
  return negative ? '-$value $currency' : '$value $currency';
}

Color statusColor(String status, BuildContext context) {
  final value = status.toUpperCase();
  switch (value) {
    case 'PENDING':
      return Colors.amber.shade700;
    case 'PAID':
    case 'CONFIRMED':
      return Colors.green.shade700;
    case 'CANCELED':
      return Colors.red.shade700;
    case 'REDEEMED':
      return Colors.blueGrey.shade700;
    default:
      return Theme.of(context).colorScheme.secondary;
  }
}

Color statusTint(String status, BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isDark) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFF5E4A13);
      case 'PAID':
      case 'CONFIRMED':
        return const Color(0xFF1F4D2B);
      case 'CANCELED':
        return const Color(0xFF5C2025);
      case 'REDEEMED':
        return const Color(0xFF24465A);
      default:
        return const Color(0xFF2B3445);
    }
  }

  switch (status.toUpperCase()) {
    case 'PENDING':
      return const Color(0xFFFFF8E1);
    case 'PAID':
    case 'CONFIRMED':
      return const Color(0xFFE8F5E9);
    case 'CANCELED':
      return const Color(0xFFFFEBEE);
    case 'REDEEMED':
      return const Color(0xFFE3F2FD);
    default:
      return const Color(0xFFF5F5F5);
  }
}
