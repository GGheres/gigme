import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

Future<void> showPurchaseTicketFlow(
  BuildContext context, {
  required int eventId,
}) {
  if (kIsWeb) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        child: SizedBox(
          width: min(MediaQuery.of(context).size.width * 0.85, 760),
          height: min(MediaQuery.of(context).size.height * 0.9, 760),
          child: PurchaseTicketFlow(eventId: eventId),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.93,
        child: PurchaseTicketFlow(eventId: eventId),
      );
    },
  );
}

class PurchaseTicketFlow extends ConsumerStatefulWidget {
  const PurchaseTicketFlow({required this.eventId, super.key});

  final int eventId;

  @override
  ConsumerState<PurchaseTicketFlow> createState() => _PurchaseTicketFlowState();
}

class _PurchaseTicketFlowState extends ConsumerState<PurchaseTicketFlow> {
  EventProductsModel? _products;
  final Map<String, int> _ticketQuantities = <String, int>{};
  String? _selectedTransferId;
  int _transferQty = 1;
  String _paymentMethod = 'PHONE';

  final TextEditingController _promoCtrl = TextEditingController();
  PromoValidationModel? _promoResult;
  bool _loading = true;
  bool _submitting = false;
  bool _validatingPromo = false;
  String? _error;
  OrderDetailModel? _createdOrder;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProducts());
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  String? get _token {
    return ref.read(authControllerProvider).state.token;
  }

  Future<void> _loadProducts() async {
    final token = _token?.trim() ?? '';
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
      final products =
          await ref.read(ticketingRepositoryProvider).getEventProducts(
                token: token,
                eventId: widget.eventId,
              );
      if (!mounted) return;
      setState(() {
        _products = products;
        for (final ticket in products.tickets) {
          _ticketQuantities.putIfAbsent(ticket.id, () => 0);
        }
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

  int get _subtotalCents {
    final products = _products;
    if (products == null) return 0;

    var subtotal = 0;
    for (final ticket in products.tickets) {
      final qty = _ticketQuantities[ticket.id] ?? 0;
      if (qty <= 0) continue;
      subtotal += ticket.priceCents * qty;
    }

    if (_selectedTransferId != null && _transferQty > 0) {
      final transfer = _selectedTransfer(products);
      if (transfer != null) {
        subtotal += transfer.priceCents * _transferQty;
      }
    }

    return subtotal;
  }

  int get _discountCents {
    final promo = _promoResult;
    if (promo == null || !promo.valid) return 0;
    return promo.discountCents;
  }

  int get _totalCents {
    final total = _subtotalCents - _discountCents;
    return max(total, 0);
  }

  Future<void> _validatePromo() async {
    final token = _token?.trim() ?? '';
    if (token.isEmpty) return;
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _promoResult = null);
      return;
    }
    final subtotal = _subtotalCents;
    if (subtotal <= 0) {
      _showMessage('Select tickets first');
      return;
    }

    setState(() => _validatingPromo = true);
    try {
      final result = await ref.read(ticketingRepositoryProvider).validatePromo(
            token: token,
            eventId: widget.eventId,
            code: code,
            subtotalCents: subtotal,
          );
      if (!mounted) return;
      setState(() => _promoResult = result);
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _validatingPromo = false);
      }
    }
  }

  Future<void> _submitOrder() async {
    final token = _token?.trim() ?? '';
    if (token.isEmpty) return;

    final ticketItems = <OrderSelectionModel>[];
    for (final entry in _ticketQuantities.entries) {
      if (entry.value <= 0) continue;
      ticketItems.add(
          OrderSelectionModel(productId: entry.key, quantity: entry.value));
    }
    if (ticketItems.isEmpty) {
      _showMessage('Select at least one ticket');
      return;
    }

    final transferItems = <OrderSelectionModel>[];
    if ((_selectedTransferId ?? '').trim().isNotEmpty && _transferQty > 0) {
      transferItems.add(OrderSelectionModel(
          productId: _selectedTransferId!, quantity: _transferQty));
    }

    setState(() => _submitting = true);
    try {
      final created = await ref.read(ticketingRepositoryProvider).createOrder(
            token: token,
            payload: CreateOrderPayload(
              eventId: widget.eventId,
              paymentMethod: _paymentMethod,
              paymentReference: '',
              ticketItems: ticketItems,
              transferItems: transferItems,
              promoCode: _promoCtrl.text.trim(),
            ),
          );
      if (!mounted) return;
      setState(() => _createdOrder = created);
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadProducts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_createdOrder != null) {
      return PurchaseStatusPage(
        detail: _createdOrder!,
        onClose: () => Navigator.of(context).maybePop(),
      );
    }

    final products = _products;
    if (products == null) {
      return const Center(child: Text('Products unavailable'));
    }

    final selectedTransfer = _selectedTransfer(products);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase ticket'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('A) Choose event ticket(s)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...products.tickets.map((ticket) => _TicketQuantityRow(
                title: ticket.label,
                subtitle: formatMoney(ticket.priceCents),
                quantity: _ticketQuantities[ticket.id] ?? 0,
                onChanged: (value) {
                  setState(() {
                    _ticketQuantities[ticket.id] = value;
                    _promoResult = null;
                  });
                },
              )),
          const SizedBox(height: 16),
          Text('B) Transfer ticket (optional)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedTransferId,
            decoration: const InputDecoration(labelText: 'Direction'),
            items: [
              const DropdownMenuItem<String>(
                  value: null, child: Text('No transfer')),
              ...products.transfers.map(
                (transfer) => DropdownMenuItem<String>(
                  value: transfer.id,
                  child: Text(
                      '${transfer.label} • ${formatMoney(transfer.priceCents)}'),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedTransferId = value;
                _promoResult = null;
              });
            },
          ),
          if (selectedTransfer != null) ...[
            const SizedBox(height: 8),
            _TicketQuantityRow(
              title: 'Transfer quantity',
              subtitle: selectedTransfer.infoLabel,
              quantity: _transferQty,
              onChanged: (value) {
                setState(() {
                  _transferQty = max(value, 1);
                  _promoResult = null;
                });
              },
            ),
          ],
          const SizedBox(height: 16),
          Text('C) Promo code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Enter promo code',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _validatingPromo ? null : _validatePromo,
                child: Text(_validatingPromo ? '...' : 'Apply'),
              ),
            ],
          ),
          if (_promoResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _promoResult!.valid
                  ? 'Discount: ${formatMoney(_promoResult!.discountCents)}'
                  : 'Promo invalid: ${_promoResult!.reason}',
              style: TextStyle(
                color: _promoResult!.valid
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Payment method',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...['PHONE', 'USDT', 'PAYMENT_QR'].map(
            (method) => RadioListTile<String>(
              value: method,
              groupValue: _paymentMethod,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _paymentMethod = value);
              },
              title: Text(_paymentLabel(method)),
            ),
          ),
          PaymentMethodPage(
            method: _paymentMethod,
            amountCents: _totalCents,
          ),
          const SizedBox(height: 16),
          Text('D) Order summary',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _SummaryRow(
              label: 'Tickets + transfer', value: formatMoney(_subtotalCents)),
          _SummaryRow(
              label: 'Discount', value: '- ${formatMoney(_discountCents)}'),
          const Divider(),
          _SummaryRow(
            label: 'Total',
            value: formatMoney(_totalCents),
            emphasized: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submitOrder,
            child: Text(_submitting ? 'Submitting…' : 'I paid'),
          ),
          const SizedBox(height: 10),
          Text(
            'After clicking "I paid" the order will be created with PENDING status.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'USDT':
        return 'Pay with USDT';
      case 'PAYMENT_QR':
        return 'Pay via QR code';
      case 'PHONE':
      default:
        return 'Pay by phone number';
    }
  }

  TransferProductModel? _selectedTransfer(EventProductsModel products) {
    final selectedId = _selectedTransferId;
    if ((selectedId ?? '').trim().isEmpty) return null;
    for (final item in products.transfers) {
      if (item.id == selectedId) return item;
    }
    return null;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class PaymentMethodPage extends StatelessWidget {
  const PaymentMethodPage({
    required this.method,
    required this.amountCents,
    super.key,
  });

  final String method;
  final int amountCents;

  @override
  Widget build(BuildContext context) {
    String hint;
    if (method == 'USDT') {
      hint = 'Wallet/network details will be shown after order creation.';
    } else if (method == 'PAYMENT_QR') {
      hint = 'Payment QR data will be generated after order creation.';
    } else {
      hint = 'Phone transfer instructions will be shown after order creation.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ${formatMoney(amountCents)}'),
            const SizedBox(height: 6),
            Text(hint),
          ],
        ),
      ),
    );
  }
}

class PurchaseStatusPage extends StatelessWidget {
  const PurchaseStatusPage({
    required this.detail,
    required this.onClose,
    super.key,
  });

  final OrderDetailModel detail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final instructions = detail.paymentInstructions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase status'),
        leading: IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusTint(order.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Waiting for confirmation (${order.status})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Order ID: ${order.id}'),
          Text('Payment method: ${order.paymentMethod}'),
          Text('Total: ${formatMoney(order.totalCents)}'),
          const SizedBox(height: 10),
          if (instructions.displayMessage.trim().isNotEmpty)
            Text(instructions.displayMessage),
          if (instructions.phoneNumber.trim().isNotEmpty)
            Text('Phone: ${instructions.phoneNumber}'),
          if (instructions.usdtWallet.trim().isNotEmpty)
            Text('USDT wallet: ${instructions.usdtWallet}'),
          if (instructions.usdtNetwork.trim().isNotEmpty)
            Text('Network: ${instructions.usdtNetwork}'),
          if (instructions.usdtMemo.trim().isNotEmpty)
            Text('Memo: ${instructions.usdtMemo}'),
          if (instructions.paymentQrData.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
                'Payment QR payload:\n${instructions.paymentQrData}'),
          ],
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onClose,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _TicketQuantityRow extends StatelessWidget {
  const _TicketQuantityRow({
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              onPressed:
                  quantity <= 0 ? null : () => onChanged(max(0, quantity - 1)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$quantity'),
            IconButton(
              onPressed: () => onChanged(quantity + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
