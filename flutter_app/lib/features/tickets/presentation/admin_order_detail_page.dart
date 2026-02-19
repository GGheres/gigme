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

class AdminOrderDetailPage extends ConsumerStatefulWidget {
  const AdminOrderDetailPage({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<AdminOrderDetailPage> createState() =>
      _AdminOrderDetailPageState();
}

class _AdminOrderDetailPageState extends ConsumerState<AdminOrderDetailPage> {
  static const int _deleteActivationTapTarget = 5;
  static const Duration _deleteActivationTapWindow = Duration(seconds: 8);

  bool _loading = true;
  bool _busy = false;
  String? _error;
  OrderDetailModel? _detail;
  int _deleteActivationTapCount = 0;
  DateTime? _lastDeleteActivationTapAt;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
      final response =
          await ref.read(ticketingRepositoryProvider).getAdminOrder(
                token: token,
                orderId: widget.orderId,
              );
      if (!mounted) return;
      setState(() {
        _detail = response;
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

  Future<void> _confirm() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await ref.read(ticketingRepositoryProvider).confirmOrder(
            token: token,
            orderId: widget.orderId,
          );
      if (!mounted) return;
      setState(() => _detail = response);
      _showMessage('Заказ подтвержден');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancel() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;

    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Отмена заказа'),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration:
                const InputDecoration(hintText: 'Причина (необязательно)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
            FilledButton(
              onPressed: () => Navigator.pop(context, reasonCtrl.text.trim()),
              child: const Text('Отменить заказ'),
            ),
          ],
        );
      },
    );
    reasonCtrl.dispose();
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      final response = await ref.read(ticketingRepositoryProvider).cancelOrder(
            token: token,
            orderId: widget.orderId,
            reason: reason,
          );
      if (!mounted) return;
      setState(() => _detail = response);
      _showMessage('Заказ отменен');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Детали заказа')),
        body: Center(child: Text(_error!)),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return const Scaffold(body: Center(child: Text('Заказ не найден')));
    }

    final order = detail.order;
    final status = order.status;
    final userTelegramId = detail.user?.telegramId ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _registerDeleteActivationTap,
          child: Text('Заказ ${order.id}'),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusTint(status, context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('Статус: ',
                    style: Theme.of(context).textTheme.titleMedium),
                Chip(
                  label: Text(status),
                  backgroundColor:
                      statusColor(status, context).withValues(alpha: 0.12),
                  side: BorderSide(color: statusColor(status, context)),
                  labelStyle: TextStyle(
                      color: statusColor(status, context),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
              'Событие: ${order.eventTitle.isEmpty ? order.eventId : order.eventTitle}'),
          Text(
              'Пользователь: ${detail.user?.displayName ?? '#${order.userId}'}'),
          if (userTelegramId > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => context.push(
                    AppRoutes.adminBotMessagesForChat(userTelegramId),
                  ),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Диалог'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openBotForUser(userTelegramId),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Открыть бота'),
                ),
              ],
            ),
          ],
          Text('Оплата: ${order.paymentMethod}'),
          if (order.paymentReference.trim().isNotEmpty)
            Text('Референс платежа: ${order.paymentReference}'),
          if (detail.paymentInstructions.paymentQrCId.trim().isNotEmpty)
            Text('SBP qrcId: ${detail.paymentInstructions.paymentQrCId}'),
          Text('Сумма без скидки: ${formatMoney(order.subtotalCents)}'),
          Text('Скидка: ${formatMoney(order.discountCents)}'),
          Text('Итого: ${formatMoney(order.totalCents)}'),
          const SizedBox(height: 12),
          Text('Позиции', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...detail.items.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${item.itemType} · ${item.productRef}'),
              subtitle: Text(
                  'Кол-во ${item.quantity}  ×  ${formatMoney(item.unitPriceCents)}'),
              trailing: Text(formatMoney(item.lineTotalCents)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Билеты', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...detail.tickets.map(
            (ticket) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Билет ${ticket.id}'),
              subtitle:
                  Text('${ticket.ticketType} · кол-во ${ticket.quantity}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Chip(
                    label: Text(ticket.status),
                    backgroundColor: statusColor(ticket.status, context)
                        .withValues(alpha: 0.12),
                    side:
                        BorderSide(color: statusColor(ticket.status, context)),
                    labelStyle: TextStyle(
                      color: statusColor(ticket.status, context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (ticket.redeemedAt != null)
                    Text(
                      ticket.redeemedAt!.toLocal().toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (status == 'PENDING') ...[
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? 'Подождите…' : 'Подтвердить оплату'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _cancel,
              child: const Text('Отменить заказ'),
            ),
          ] else if (status == 'PAID' || status == 'CONFIRMED') ...[
            FilledButton.tonal(
              onPressed: _busy ? null : _cancel,
              child: const Text('Отменить заказ'),
            ),
          ],
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  void _registerDeleteActivationTap() {
    final now = DateTime.now();
    final lastTap = _lastDeleteActivationTapAt;
    if (lastTap == null ||
        now.difference(lastTap) > _deleteActivationTapWindow) {
      _deleteActivationTapCount = 0;
    }

    _lastDeleteActivationTapAt = now;
    _deleteActivationTapCount += 1;
    if (_deleteActivationTapCount < _deleteActivationTapTarget) {
      return;
    }

    _deleteActivationTapCount = 0;
    unawaited(_promptDeleteOrder());
  }

  Future<void> _promptDeleteOrder() async {
    if (_busy) return;
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;

    final passwordCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Удаление заказа'),
          content: TextField(
            controller: passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              hintText: 'Введите пароль для удаления',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, passwordCtrl.text.trim()),
              child: const Text('Продолжить'),
            ),
          ],
        );
      },
    );
    passwordCtrl.dispose();
    if (!mounted) return;
    if ((password ?? '').trim().isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить заказ?'),
        content: const Text(
            'Заказ будет удален из базы без возможности восстановления.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).deleteAdminOrder(
            token: token,
            orderId: widget.orderId,
            password: password!,
          );
      if (!mounted) return;
      _showMessage('Заказ удален');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go(AppRoutes.adminOrders);
      }
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
