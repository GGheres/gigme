import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/routes.dart';
import '../../auth/application/auth_controller.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// MyTicketsPage represents my tickets page.

class MyTicketsPage extends ConsumerStatefulWidget {
  /// MyTicketsPage handles my tickets page.
  const MyTicketsPage({super.key});

  /// createState creates state.

  @override
  ConsumerState<MyTicketsPage> createState() => _MyTicketsPageState();
}

/// _MyTicketsPageState represents my tickets page state.

class _MyTicketsPageState extends ConsumerState<MyTicketsPage> {
  bool _loading = true;
  String? _error;
  List<TicketModel> _tickets = <TicketModel>[];

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// _load loads data from the underlying source.

  Future<void> _load() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Требуется авторизация';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ref
          .read(ticketingRepositoryProvider)
          .listMyTickets(token: token);
      if (!mounted) return;
      setState(() {
        _tickets = response.items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
      ),
      title: 'Мои билеты',
      subtitle: 'Все активные и использованные билеты',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              label: 'Обновить',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
              outline: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _loading
                ? const Center(
                    child: LoadingState(
                      title: 'Загрузка билетов',
                      subtitle: 'Проверяем активные заказы',
                    ),
                  )
                : (_error != null)
                    ? Center(
                        child: ErrorState(
                          message: _error!,
                          onRetry: _load,
                        ),
                      )
                    : _tickets.isEmpty
                        ? const Center(
                            child: EmptyState(
                              title: 'Билетов пока нет',
                              subtitle:
                                  'После подтверждения заказа здесь появится QR-код',
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _tickets.length,
                            itemBuilder: (context, index) {
                              final ticket = _tickets[index];
                              final status = ticket.status;
                              final isCanceled = status == 'CANCELED';
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  variant: AppCardVariant.surface,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Билет ${ticket.id}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                          ),
                                          Chip(
                                            label: Text(status),
                                            backgroundColor:
                                                statusColor(status, context)
                                                    .withValues(alpha: 0.12),
                                            side: BorderSide(
                                              color:
                                                  statusColor(status, context),
                                            ),
                                            labelStyle: TextStyle(
                                              color:
                                                  statusColor(status, context),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Тип: ${ticket.ticketType} · Кол-во: ${ticket.quantity}',
                                      ),
                                      if (ticket.redeemedAt != null)
                                        Text(
                                          'Погашен: ${ticket.redeemedAt!.toLocal()}',
                                        ),
                                      const SizedBox(height: AppSpacing.sm),
                                      if (isCanceled)
                                        const Text(
                                          'Заказ отменен. Билет недействителен.',
                                        )
                                      else if (ticket.qrPayload
                                          .trim()
                                          .isNotEmpty)
                                        Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceStrong,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: QrImageView(
                                              data: ticket.qrPayload,
                                              size: 180,
                                              backgroundColor: Colors.white,
                                            ),
                                          ),
                                        )
                                      else
                                        const Text(
                                          'QR-код появится после подтверждения оплаты.',
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  /// _handleBack handles back.

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go(AppRoutes.profile);
  }
}
