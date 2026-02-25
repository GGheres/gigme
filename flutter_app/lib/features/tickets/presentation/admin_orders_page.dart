import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminOrdersPage represents admin orders page.

class AdminOrdersPage extends ConsumerStatefulWidget {
  /// AdminOrdersPage handles admin orders page.
  const AdminOrdersPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  /// createState creates state.

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

/// _AdminOrdersPageState represents admin orders page state.

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  String _status = '';
  bool _loading = true;
  String? _error;
  OrdersListModel? _orders;

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

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final items = _orders?.items ?? <OrderSummaryModel>[];

    final body = _buildBody(context, items);
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-заказы'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: body,
    );
  }

  /// _buildBody builds body.

  Widget _buildBody(BuildContext context, List<OrderSummaryModel> items) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _eventIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'ID события'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Статус'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Все')),
                    DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
                    DropdownMenuItem(value: 'PAID', child: Text('PAID')),
                    DropdownMenuItem(
                        value: 'CONFIRMED', child: Text('CONFIRMED')),
                    DropdownMenuItem(
                        value: 'CANCELED', child: Text('CANCELED')),
                    DropdownMenuItem(
                        value: 'REDEEMED', child: Text('REDEEMED')),
                  ],
                  onChanged: (value) => setState(() => _status = value ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _load, child: const Text('Загрузить')),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
                  ? Center(child: Text(_error!))
                  : items.isEmpty
                      ? const Center(child: Text('Заказов нет'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final order = item.order;
                            final status = order.status;
                            final userTelegramId = item.user?.telegramId ?? 0;
                            final userDisplay = item.user?.displayName ??
                                'Пользователь #${order.userId}';
                            final userHandle = item.user?.usernameLabel ?? '';
                            final subtitleLines = <String>[
                              'Заказ ${order.id}',
                              userDisplay,
                            ];
                            if (userHandle.isNotEmpty &&
                                userHandle != userDisplay.trim()) {
                              subtitleLines.add(userHandle);
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: statusTint(status, context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: ListTile(
                                onTap: () => context
                                    .push(AppRoutes.adminOrderDetail(order.id)),
                                title: Text(order.eventTitle.isEmpty
                                    ? 'Событие #${order.eventId}'
                                    : order.eventTitle),
                                subtitle: Text(
                                  subtitleLines.join('\n'),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (userTelegramId > 0)
                                      IconButton(
                                        tooltip: 'Диалог',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => context.push(
                                          AppRoutes.adminBotMessagesForChat(
                                              userTelegramId),
                                        ),
                                        icon: const Icon(Icons.forum_outlined),
                                      ),
                                    if (userTelegramId > 0)
                                      IconButton(
                                        tooltip: 'Открыть бота',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _openBotForUser(userTelegramId),
                                        icon: const Icon(
                                            Icons.open_in_new_rounded),
                                      ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Chip(
                                          label: Text(status),
                                          backgroundColor:
                                              statusColor(status, context)
                                                  .withValues(alpha: 0.12),
                                          side: BorderSide(
                                            color: statusColor(status, context),
                                          ),
                                          labelStyle: TextStyle(
                                            color: statusColor(status, context),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(formatMoney(order.totalCents)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  /// _openBotForUser handles open bot for user.

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

  /// _showMessage handles show message.

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
