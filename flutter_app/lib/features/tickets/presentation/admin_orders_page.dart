import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../../ui/components/admin_filter_bar.dart';
import '../../../ui/components/admin_list_item.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'order_status.dart';
import 'ticketing_ui_utils.dart';

/// Admin page listing orders with filters and status-aware list items.
class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  String _status = '';
  bool _loading = true;
  String? _error;
  OrdersListModel? _orders;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _eventIdCtrl.dispose();
    super.dispose();
  }

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
          await ref.read(ticketingRepositoryProvider).listAdminOrders(
                token: token,
                eventId: (eventId ?? 0) > 0 ? eventId : null,
                status: _status.trim().isEmpty ? null : _status,
              );
      if (!mounted) return;
      setState(() {
        _orders = response;
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

  @override
  Widget build(BuildContext context) {
    final items = _orders?.items ?? <OrderSummaryModel>[];
    final body = _buildBody(context, items);
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-заказы'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, List<OrderSummaryModel> items) {
    final totalAmount = items.fold<int>(
      0,
      (sum, item) => sum + item.order.totalCents,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHero(
          title: 'Заказы',
          subtitle: 'Фильтруйте по событию и статусу, открывайте детали заказа',
          leadingIcon: Icons.receipt_long_rounded,
          metrics: [
            heroMetric('Всего', '${items.length}',
                icon: Icons.confirmation_number_outlined),
            if (items.isNotEmpty)
              heroMetric('Сумма', formatMoney(totalAmount),
                  icon: Icons.payments_outlined),
          ],
        ),
        AdminFilterBar(
          fields: [
            TextField(
              controller: _eventIdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ID события',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              onSubmitted: (_) => _load(),
            ),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Статус',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Все')),
                for (final status in OrderStatus.values.where(
                    (s) => s != OrderStatus.unknown))
                  DropdownMenuItem(
                      value: status.code, child: Text(status.label)),
              ],
              onChanged: (value) => setState(() => _status = value ?? ''),
            ),
          ],
          actions: [
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Применить'),
            ),
          ],
        ),
        if ((_error ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: InlineStatusBanner(
              title: 'Не удалось загрузить заказы',
              message: _error!,
              onRetry: _load,
            ),
          ),
        Expanded(
          child: _buildList(items),
        ),
      ],
    );
  }

  Widget _buildList(List<OrderSummaryModel> items) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty && (_error ?? '').isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: EmptyState(
          title: 'Заказов нет',
          subtitle: 'Попробуйте изменить фильтры или сбросить их.',
          icon: Icons.inbox_outlined,
          actionLabel: 'Сбросить фильтры',
          onAction: () {
            setState(() {
              _eventIdCtrl.clear();
              _status = '';
            });
            unawaited(_load());
          },
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildItem(context, items[index]),
    );
  }

  Widget _buildItem(BuildContext context, OrderSummaryModel item) {
    final order = item.order;
    final status = OrderStatus.fromCode(order.status);
    final palette = OrderStatusPalette.of(status, context);

    final userTelegramId = item.user?.telegramId ?? 0;
    final userDisplay =
        item.user?.displayName ?? 'Пользователь #${order.userId}';
    final userHandle = item.user?.usernameLabel ?? '';

    final subtitleLines = <String>[
      'Заказ ${order.id}',
      userDisplay,
    ];
    if (userHandle.isNotEmpty && userHandle != userDisplay.trim()) {
      subtitleLines.add(userHandle);
    }

    return AdminListItem(
      onTap: () => context.push(AppRoutes.adminOrderDetail(order.id)),
      title: order.eventTitle.isEmpty
          ? 'Событие #${order.eventId}'
          : order.eventTitle,
      subtitleLines: subtitleLines,
      status: AdminListItemStatus(
        label: status.code,
        foreground: palette.foreground,
        tint: palette.tint,
      ),
      trailingValue: formatMoney(order.totalCents),
      actions: [
        if (userTelegramId > 0)
          IconButton(
            tooltip: 'Диалог',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.push(
              AppRoutes.adminBotMessagesForChat(userTelegramId),
            ),
            icon: const Icon(Icons.forum_outlined),
          ),
        if (userTelegramId > 0)
          IconButton(
            tooltip: 'Открыть бота',
            visualDensity: VisualDensity.compact,
            onPressed: () => _openBotForUser(userTelegramId),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
      ],
    );
  }

  Future<void> _openBotForUser(int telegramId) async {
    final config = ref.read(appConfigProvider);
    final link = buildBotReplyDeepLink(
      botUsername: config.botUsername,
      telegramId: telegramId,
    );
    if (link.isEmpty) {
      _showMessage('BOT_USERNAME не настроен');
      return;
    }

    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('Не удалось открыть Telegram');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
