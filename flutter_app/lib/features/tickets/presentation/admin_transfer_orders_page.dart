import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminTransferOrdersPage represents admin transfer orders page.

class AdminTransferOrdersPage extends ConsumerStatefulWidget {
  /// AdminTransferOrdersPage handles admin transfer orders page.
  const AdminTransferOrdersPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  /// createState creates state.

  @override
  ConsumerState<AdminTransferOrdersPage> createState() =>
      _AdminTransferOrdersPageState();
}

/// _AdminTransferOrdersPageState represents admin transfer orders page state.

class _AdminTransferOrdersPageState
    extends ConsumerState<AdminTransferOrdersPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  String _status = '';
  bool _loading = true;
  String? _error;
  AdminTransferOrdersListModel? _transfers;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// dispose releases resources held by this instance.

  @override
  void dispose() {
    _eventIdCtrl.dispose();
    super.dispose();
  }

  /// _load loads ordered transfer rows.

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
      final eventId = int.tryParse(_eventIdCtrl.text.trim());
      final response =
          await ref.read(ticketingRepositoryProvider).listAdminTransferOrders(
                token: token,
                eventId: (eventId ?? 0) > 0 ? eventId : null,
                status: _status.trim().isEmpty ? null : _status,
              );
      if (!mounted) return;
      setState(() {
        _transfers = response;
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
    final items = _transfers?.items ?? <AdminTransferOrderModel>[];
    final body = _buildBody(context, items);
    if (widget.embedded) return body;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Админ-трансферы'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      title: 'Трансферы',
      subtitle: 'Отдельный список заказанных мест на трансфер',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74),
      child: body,
    );
  }

  /// _buildBody builds the transfer orders body.

  Widget _buildBody(
    BuildContext context,
    List<AdminTransferOrderModel> items,
  ) {
    final totalSeats = items.fold<int>(
      0,
      (sum, item) => sum + item.item.quantity,
    );

    return Column(
      children: [
        ScreenHero(
          title: 'Заказанные трансферы',
          subtitle: 'Контроль мест, статусов оплаты и пользователей.',
          summary: [
            AppBadge(
              label: '${items.length} заказов',
              variant: AppBadgeVariant.neutral,
            ),
            AppBadge(
              label: '$totalSeats мест',
              variant: AppBadgeVariant.info,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Фильтры',
          subtitle: 'Сузьте список по событию и статусу заказа',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputField(
                      controller: _eventIdCtrl,
                      keyboardType: TextInputType.number,
                      label: 'ID события',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Статус'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Все')),
                        DropdownMenuItem(
                          value: 'PENDING',
                          child: Text('PENDING'),
                        ),
                        DropdownMenuItem(value: 'PAID', child: Text('PAID')),
                        DropdownMenuItem(
                          value: 'CONFIRMED',
                          child: Text('CONFIRMED'),
                        ),
                        DropdownMenuItem(
                          value: 'CANCELED',
                          child: Text('CANCELED'),
                        ),
                        DropdownMenuItem(
                          value: 'REDEEMED',
                          child: Text('REDEEMED'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                onPressed: _loading ? null : _load,
                label: _loading ? 'Загрузка…' : 'Применить фильтры',
                expand: true,
              ),
            ],
          ),
        ),
        if ((_error ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineStatusBanner(
            title: 'Не удалось загрузить трансферы',
            message: _error!,
            tone: InlineStatusBannerTone.danger,
            actionLabel: 'Повторить',
            onAction: _load,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _loading
              ? const Center(
                  child: LoadingState(
                    title: 'Загрузка трансферов',
                    subtitle: 'Получаем заказанные места',
                  ),
                )
              : (_error != null)
                  ? const SizedBox.shrink()
                  : items.isEmpty
                      ? const Center(
                          child: EmptyState(
                            title: 'Трансферов нет',
                            subtitle: 'Пока нет заказанных трансферов.',
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _TransferOrderCard(item: item);
                          },
                        ),
        ),
      ],
    );
  }
}

/// _TransferOrderCard represents an ordered transfer card.

class _TransferOrderCard extends StatelessWidget {
  /// _TransferOrderCard handles ordered transfer card.
  const _TransferOrderCard({required this.item});

  final AdminTransferOrderModel item;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final userDisplay =
        item.user?.displayName ?? 'Пользователь #${item.userId}';
    final createdAt = item.orderCreatedAt?.toLocal().toString() ?? '';
    final title =
        item.eventTitle.isEmpty ? 'Событие #${item.eventId}' : item.eventTitle;
    final status = item.orderStatus;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        variant: AppCardVariant.plain,
        child: InkWell(
          onTap: () => context.push(AppRoutes.adminOrderDetail(item.orderId)),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.airport_shuttle_rounded),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Chip(
                      label: Text(status),
                      backgroundColor:
                          statusColor(status, context).withValues(alpha: 0.12),
                      side: BorderSide(
                        color: statusColor(status, context),
                      ),
                      labelStyle: TextStyle(
                        color: statusColor(status, context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Заказ ${item.orderId}'),
                Text(userDisplay),
                Text(item.item.displayName),
                if (createdAt.isNotEmpty) Text(createdAt),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    AppBadge(
                      label: '${item.item.quantity} мест',
                      variant: AppBadgeVariant.info,
                    ),
                    AppBadge(
                      label: formatMoney(item.item.lineTotalCents),
                      variant: AppBadgeVariant.ghost,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
