import 'package:flutter/material.dart';

import '../../../../ui/components/app_badge.dart';
import '../../../../ui/components/app_card.dart';
import '../../../../ui/components/psychedelic_qr_card.dart';
import '../../../../ui/theme/app_spacing.dart';
import '../../domain/ticketing_models.dart';

/// TicketCard represents ticket card.

class TicketCard extends StatelessWidget {
  /// TicketCard handles ticket card.
  const TicketCard({
    required this.ticket,
    super.key,
  });

  final TicketModel ticket;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final status = ticket.status.toUpperCase();
    final isCanceled = status == 'CANCELED';
    final isRedeemed = status == 'REDEEMED';
    final hasQr = ticket.qrPayload.trim().isNotEmpty;
    final entityLabel = ticket.isTransfer ? 'Трансфер' : 'Билет';
    final badgeVariant = _badgeVariantFor(status);
    final metaStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.78),
        );

    return AppCard(
      variant: AppCardVariant.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useColumn = constraints.maxWidth < 420;
              final badge = AppBadge(
                label: _statusLabel(status),
                variant: badgeVariant,
              );

              if (useColumn) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$entityLabel #${ticket.id}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    badge,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      '$entityLabel #${ticket.id}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  badge,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            ticket.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                ticket.isTransfer
                    ? 'Мест: ${ticket.quantity}'
                    : 'Количество: ${ticket.quantity}',
                style: metaStyle,
              ),
              if (ticket.redeemedAt != null)
                Text(
                  'Погашен: ${ticket.redeemedAt!.toLocal()}',
                  style: metaStyle,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isCanceled)
            Text(
              'Заказ отменен. Билет недействителен.',
              style: metaStyle,
            )
          else if (hasQr)
            Center(
              child: Opacity(
                opacity: isRedeemed ? 0.7 : 1,
                child: PsychedelicQrCard(
                  data: ticket.qrPayload,
                  caption: isRedeemed
                      ? '$entityLabel уже использован'
                      : ticket.isTransfer
                          ? 'Покажите QR-код при посадке'
                          : 'Покажите QR-код на входе',
                  size: 176,
                ),
              ),
            )
          else
            Text(
              'QR-код появится после подтверждения оплаты.',
              style: metaStyle,
            ),
        ],
      ),
    );
  }

  /// _badgeVariantFor handles badge variant for.

  AppBadgeVariant _badgeVariantFor(String status) {
    switch (status) {
      case 'PAID':
      case 'CONFIRMED':
        return AppBadgeVariant.success;
      case 'PENDING':
        return AppBadgeVariant.accent;
      case 'CANCELED':
        return AppBadgeVariant.danger;
      case 'REDEEMED':
        return AppBadgeVariant.info;
      default:
        return AppBadgeVariant.neutral;
    }
  }

  /// _statusLabel handles status label.

  String _statusLabel(String status) {
    switch (status) {
      case 'PAID':
        return 'Оплачен';
      case 'CONFIRMED':
        return 'Подтвержден';
      case 'PENDING':
        return 'Ожидает оплату';
      case 'CANCELED':
        return 'Отменен';
      case 'REDEEMED':
        return 'Использован';
      default:
        return status;
    }
  }
}
