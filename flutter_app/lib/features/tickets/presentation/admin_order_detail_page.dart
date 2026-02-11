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
        _error = 'Authorization required';
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
      _showMessage('Order confirmed');
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
          title: const Text('Cancel order'),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason (optional)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
            FilledButton(
              onPressed: () => Navigator.pop(context, reasonCtrl.text.trim()),
              child: const Text('Cancel order'),
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
      _showMessage('Order canceled');
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
        appBar: AppBar(title: const Text('Order details')),
        body: Center(child: Text(_error!)),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return const Scaffold(body: Center(child: Text('Order not found')));
    }

    final order = detail.order;
    final status = order.status;

    return Scaffold(
      appBar: AppBar(
        title: Text('Order ${order.id}'),
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
              color: statusTint(status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('Status: ',
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
              'Event: ${order.eventTitle.isEmpty ? order.eventId : order.eventTitle}'),
          Text('User: ${detail.user?.displayName ?? '#${order.userId}'}'),
          Text('Payment: ${order.paymentMethod}'),
          if (order.paymentReference.trim().isNotEmpty)
            Text('Payment reference: ${order.paymentReference}'),
          Text('Subtotal: ${formatMoney(order.subtotalCents)}'),
          Text('Discount: ${formatMoney(order.discountCents)}'),
          Text('Total: ${formatMoney(order.totalCents)}'),
          const SizedBox(height: 12),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...detail.items.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${item.itemType} · ${item.productRef}'),
              subtitle: Text(
                  'Qty ${item.quantity}  ×  ${formatMoney(item.unitPriceCents)}'),
              trailing: Text(formatMoney(item.lineTotalCents)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Tickets', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...detail.tickets.map(
            (ticket) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Ticket ${ticket.id}'),
              subtitle: Text('${ticket.ticketType} · qty ${ticket.quantity}'),
              trailing: ticket.redeemedAt == null
                  ? const Text('Not redeemed')
                  : Text('Redeemed\n${ticket.redeemedAt!.toLocal()}'),
            ),
          ),
          const SizedBox(height: 14),
          if (status == 'PENDING') ...[
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? 'Please wait…' : 'Confirm payment'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('Cancel order'),
            ),
          ] else if (status == 'CONFIRMED') ...[
            OutlinedButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('Cancel order'),
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
