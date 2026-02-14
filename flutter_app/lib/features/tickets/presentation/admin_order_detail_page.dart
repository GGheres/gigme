import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _loading = true;
  bool _busy = false;
  String? _error;
  OrderDetailModel? _detail;

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

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ ${order.id}'),
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
}
