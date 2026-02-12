import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

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
        _error = 'Authorization required';
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
        title: const Text('Admin orders'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: body,
    );
  }

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
                  decoration: const InputDecoration(labelText: 'Event ID'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All')),
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
              FilledButton(onPressed: _load, child: const Text('Load')),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
                  ? Center(child: Text(_error!))
                  : items.isEmpty
                      ? const Center(child: Text('No orders'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final order = item.order;
                            final status = order.status;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: statusTint(status),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: ListTile(
                                onTap: () => context
                                    .push(AppRoutes.adminOrderDetail(order.id)),
                                title: Text(order.eventTitle.isEmpty
                                    ? 'Event #${order.eventId}'
                                    : order.eventTitle),
                                subtitle: Text(
                                    'Order ${order.id}\n${item.user?.displayName ?? 'User #${order.userId}'}'),
                                trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Chip(
                                      label: Text(status),
                                      backgroundColor:
                                          statusColor(status, context)
                                              .withValues(alpha: 0.12),
                                      side: BorderSide(
                                          color: statusColor(status, context)),
                                      labelStyle: TextStyle(
                                          color: statusColor(status, context),
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(formatMoney(order.totalCents)),
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
}
