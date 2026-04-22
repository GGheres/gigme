import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';

/// Semantic order status used across admin list views.
enum OrderStatus {
  pending('PENDING', 'Ожидает'),
  paid('PAID', 'Оплачен'),
  confirmed('CONFIRMED', 'Подтверждён'),
  canceled('CANCELED', 'Отменён'),
  redeemed('REDEEMED', 'Погашен'),
  unknown('UNKNOWN', '—');

  const OrderStatus(this.code, this.label);

  final String code;
  final String label;

  static OrderStatus fromCode(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    for (final status in OrderStatus.values) {
      if (status.code == normalized) return status;
    }
    return OrderStatus.unknown;
  }
}

/// Semantic status palette — foreground and tinted background per brightness.
class OrderStatusPalette {
  const OrderStatusPalette({
    required this.foreground,
    required this.tint,
  });

  final Color foreground;
  final Color tint;

  static OrderStatusPalette of(OrderStatus status, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (status) {
      case OrderStatus.pending:
        return OrderStatusPalette(
          foreground: AppColors.warning,
          tint: isDark
              ? AppColors.warning.withValues(alpha: 0.18)
              : AppColors.warning.withValues(alpha: 0.12),
        );
      case OrderStatus.paid:
      case OrderStatus.confirmed:
        return OrderStatusPalette(
          foreground: AppColors.success,
          tint: isDark
              ? AppColors.success.withValues(alpha: 0.18)
              : AppColors.success.withValues(alpha: 0.12),
        );
      case OrderStatus.canceled:
        return OrderStatusPalette(
          foreground: AppColors.danger,
          tint: isDark
              ? AppColors.danger.withValues(alpha: 0.18)
              : AppColors.danger.withValues(alpha: 0.10),
        );
      case OrderStatus.redeemed:
        return OrderStatusPalette(
          foreground: AppColors.info,
          tint: isDark
              ? AppColors.info.withValues(alpha: 0.18)
              : AppColors.info.withValues(alpha: 0.12),
        );
      case OrderStatus.unknown:
        final fallback = Theme.of(context).colorScheme.secondary;
        return OrderStatusPalette(
          foreground: fallback,
          tint: fallback.withValues(alpha: 0.10),
        );
    }
  }
}
