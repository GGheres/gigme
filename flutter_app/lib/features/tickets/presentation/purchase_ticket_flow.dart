import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/providers.dart';
import '../../../core/notifications/providers.dart';
import '../../../ui/components/app_toast.dart';
import '../../auth/application/auth_controller.dart';
import '../data/purchase_ticket_draft_store.dart';
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

class _PurchaseTicketFlowState extends ConsumerState<PurchaseTicketFlow>
    with WidgetsBindingObserver {
  static const List<String> _allPaymentMethods = <String>[
    'PHONE',
    'USDT',
    'PAYMENT_QR',
    'TOCHKA_SBP_QR',
  ];

  final _draftStore = PurchaseTicketDraftStore();
  EventProductsModel? _products;
  PaymentSettingsModel? _paymentSettings;
  final Map<String, int> _ticketQuantities = <String, int>{};
  String? _selectedTransferId;
  int _transferQty = 1;
  String _paymentMethod = 'PHONE';

  final TextEditingController _promoCtrl = TextEditingController();
  PromoValidationModel? _promoResult;
  bool _loading = true;
  bool _submitting = false;
  bool _validatingPromo = false;
  bool _showPaymentCheckout = false;
  String? _error;
  OrderDetailModel? _createdOrder;
  CreateSbpQrOrderResponseModel? _createdSbpOrder;
  bool _restoringDraft = false;
  bool _orderCompleted = false;
  bool _showResumeReminder = false;
  Timer? _draftSaveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      ref.read(localReminderServiceProvider).cancelPurchaseReminder(
            eventId: widget.eventId,
          ),
    );
    _promoCtrl.addListener(_onDraftChanged);
    unawaited(_bootstrapFlow());
  }

  @override
  void dispose() {
    final draftBeforeDispose = _snapshotDraft();
    WidgetsBinding.instance.removeObserver(this);
    _promoCtrl.removeListener(_onDraftChanged);
    _draftSaveDebounce?.cancel();
    if (!_orderCompleted) {
      if (draftBeforeDispose.hasMeaningfulData) {
        unawaited(
          ref.read(localReminderServiceProvider).schedulePurchaseReminder(
                eventId: widget.eventId,
              ),
        );
      } else {
        unawaited(
          ref.read(localReminderServiceProvider).cancelPurchaseReminder(
                eventId: widget.eventId,
              ),
        );
      }
      unawaited(_persistDraft());
    }
    _promoCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_persistDraft());
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final draft = _snapshotDraft();
      if (draft.hasMeaningfulData) {
        _showResumeReminder = true;
        unawaited(
          ref.read(localReminderServiceProvider).schedulePurchaseReminder(
                eventId: widget.eventId,
              ),
        );
      } else {
        unawaited(
          ref.read(localReminderServiceProvider).cancelPurchaseReminder(
                eventId: widget.eventId,
              ),
        );
      }
      unawaited(_persistDraft());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(localReminderServiceProvider).cancelPurchaseReminder(
              eventId: widget.eventId,
            ),
      );
      if (_showResumeReminder) {
        _showResumeReminder = false;
        final draft = _snapshotDraft();
        if (!draft.hasMeaningfulData || !mounted) return;
        AppToast.show(
          context,
          message:
              'Черновик покупки сохранен. Завершите заказ, когда будете готовы.',
          tone: AppToastTone.warning,
        );
      }
    }
  }

  Future<void> _bootstrapFlow() async {
    await _restoreDraft();
    await _loadProducts();
  }

  void _onDraftChanged() {
    if (_restoringDraft) return;
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _orderCompleted) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_persistDraft());
    });
  }

  Future<void> _restoreDraft() async {
    _restoringDraft = true;
    try {
      final draft = await _draftStore.load(eventId: widget.eventId);
      if (!mounted || draft == null) return;

      setState(() {
        _ticketQuantities
          ..clear()
          ..addAll(draft.ticketQuantities);
        _selectedTransferId = draft.selectedTransferId;
        _transferQty = draft.transferQty;
        _paymentMethod = draft.paymentMethod;
        _promoCtrl.text = draft.promoCode;
        _showPaymentCheckout = draft.showPaymentCheckout;
        _promoResult = null;
      });

      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Восстановили незавершенный заказ. Продолжите покупку.',
        tone: AppToastTone.warning,
      );
    } finally {
      _restoringDraft = false;
    }
  }

  PurchaseTicketDraft _snapshotDraft() {
    final cleanQuantities = <String, int>{};
    _ticketQuantities.forEach((key, value) {
      if (value <= 0) return;
      cleanQuantities[key] = value.clamp(1, 20).toInt();
    });

    return PurchaseTicketDraft(
      ticketQuantities: cleanQuantities,
      selectedTransferId: _selectedTransferId,
      transferQty: _transferQty,
      paymentMethod: _paymentMethod,
      promoCode: _promoCtrl.text,
      showPaymentCheckout: _showPaymentCheckout,
    );
  }

  Future<void> _persistDraft() async {
    if (_restoringDraft || _orderCompleted) return;
    _draftSaveDebounce?.cancel();
    await _draftStore.save(
      eventId: widget.eventId,
      draft: _snapshotDraft(),
    );
  }

  void _updateStateAndSave(VoidCallback updateState) {
    setState(updateState);
    _scheduleDraftSave();
  }

  String? get _token {
    return ref.read(authControllerProvider).state.token;
  }

  List<String> get _availablePaymentMethods {
    final settings = _paymentSettings;
    if (settings == null) return _allPaymentMethods;
    return _allPaymentMethods
        .where((method) => settings.isMethodEnabled(method))
        .toList();
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
      final repo = ref.read(ticketingRepositoryProvider);
      final products = await repo.getEventProducts(
        token: token,
        eventId: widget.eventId,
      );
      PaymentSettingsModel? paymentSettings;
      try {
        paymentSettings = await repo.getPaymentSettings(token: token);
      } catch (_) {
        paymentSettings = null;
      }
      if (!mounted) return;
      setState(() {
        _products = products;
        _paymentSettings = paymentSettings;
        final activeTicketIds =
            products.tickets.map((ticket) => ticket.id).toSet();
        _ticketQuantities.removeWhere(
          (ticketId, _) => !activeTicketIds.contains(ticketId),
        );
        final selectedTransferId = _selectedTransferId;
        if ((selectedTransferId ?? '').trim().isNotEmpty) {
          final hasSelectedActiveTransfer = products.transfers.any(
            (item) => item.isActive && item.id == selectedTransferId,
          );
          if (!hasSelectedActiveTransfer) {
            _selectedTransferId = null;
            _transferQty = 1;
            _promoResult = null;
          }
        }
        final availableMethods = _availablePaymentMethods;
        if (availableMethods.isNotEmpty &&
            !availableMethods.contains(_paymentMethod)) {
          _paymentMethod = availableMethods.first;
        }
        for (final ticket in products.tickets) {
          final current = _ticketQuantities[ticket.id] ?? 0;
          _ticketQuantities[ticket.id] = current.clamp(0, 20).toInt();
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

  bool get _hasSelectedTickets {
    for (final qty in _ticketQuantities.values) {
      if (qty > 0) return true;
    }
    return false;
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
    final availableMethods = _availablePaymentMethods;
    if (availableMethods.isEmpty) {
      _showMessage('Сейчас нет доступных способов оплаты');
      return;
    }
    if (!availableMethods.contains(_paymentMethod)) {
      _showMessage('Выбранный способ оплаты недоступен');
      return;
    }

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
      final payload = CreateOrderPayload(
        eventId: widget.eventId,
        paymentMethod: _paymentMethod,
        paymentReference: '',
        ticketItems: ticketItems,
        transferItems: transferItems,
        promoCode: _promoCtrl.text.trim(),
      );
      if (_paymentMethod == 'TOCHKA_SBP_QR') {
        final created =
            await ref.read(ticketingRepositoryProvider).createSbpQrOrder(
                  token: token,
                  payload: payload,
                );
        await _draftStore.clear(eventId: widget.eventId);
        await ref
            .read(localReminderServiceProvider)
            .cancelPurchaseReminder(eventId: widget.eventId);
        _orderCompleted = true;
        if (!mounted) return;
        setState(() => _createdSbpOrder = created);
      } else {
        final created = await ref.read(ticketingRepositoryProvider).createOrder(
              token: token,
              payload: payload,
            );
        await _draftStore.clear(eventId: widget.eventId);
        await ref
            .read(localReminderServiceProvider)
            .cancelPurchaseReminder(eventId: widget.eventId);
        _orderCompleted = true;
        if (!mounted) return;
        setState(() => _createdOrder = created);
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _openPaymentCheckout() {
    if (!_hasSelectedTickets) {
      _showMessage('Сначала выберите хотя бы один билет');
      return;
    }
    final availableMethods = _availablePaymentMethods;
    if (availableMethods.isEmpty) {
      _showMessage('Сейчас нет доступных способов оплаты');
      return;
    }
    _updateStateAndSave(() {
      if (!availableMethods.contains(_paymentMethod)) {
        _paymentMethod = availableMethods.first;
      }
      _showPaymentCheckout = true;
    });
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

    if (_createdSbpOrder != null) {
      return SbpQrPaymentPage(
        created: _createdSbpOrder!,
        onClose: () => Navigator.of(context).maybePop(),
      );
    }

    if (_showPaymentCheckout) {
      return _PaymentCheckoutPage(
        paymentMethod: _paymentMethod,
        amountCents: _totalCents,
        paymentSettings: _paymentSettings,
        onBack: () => _updateStateAndSave(() => _showPaymentCheckout = false),
        onPaid: _submitting ? null : _submitOrder,
        submitting: _submitting,
      );
    }

    final products = _products;
    final availablePaymentMethods = _availablePaymentMethods;
    if (products == null) {
      return const Center(child: Text('Products unavailable'));
    }

    final activeTransfers = _activeTransfers(products);
    final selectedTransfer = _selectedTransfer(products);
    final hasTicketProducts = products.tickets.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Покупка билета'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '1) Выберите билеты',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!hasTicketProducts)
            const _InfoCard(
              text:
                  'Для этого события пока не настроены типы билетов. Попросите администратора добавить ticket products.',
            )
          else
            ...products.tickets.map(
              (ticket) => _TicketQuantityRow(
                title: ticket.label,
                subtitle: formatMoney(ticket.priceCents),
                quantity: _ticketQuantities[ticket.id] ?? 0,
                onChanged: (value) {
                  _updateStateAndSave(() {
                    _ticketQuantities[ticket.id] = value.clamp(0, 20).toInt();
                    _promoResult = null;
                  });
                },
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '2) Добавьте трансфер (опционально)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (activeTransfers.isEmpty)
            const _InfoCard(text: 'Трансфер для этого события недоступен.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Без трансфера'),
                  selected:
                      _selectedTransferId == null || selectedTransfer == null,
                  onSelected: (_) {
                    _updateStateAndSave(() {
                      _selectedTransferId = null;
                      _promoResult = null;
                    });
                  },
                ),
                ...activeTransfers.map(
                  (transfer) => ChoiceChip(
                    label: Text(
                        '${transfer.label} · ${formatMoney(transfer.priceCents)}'),
                    selected: _selectedTransferId == transfer.id,
                    onSelected: (_) {
                      _updateStateAndSave(() {
                        _selectedTransferId = transfer.id;
                        _promoResult = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          if (selectedTransfer != null) ...[
            const SizedBox(height: 8),
            if (selectedTransfer.infoLabel.trim().isNotEmpty)
              _InfoCard(text: selectedTransfer.infoLabel),
            _TicketQuantityRow(
              title: 'Количество трансфера',
              subtitle: formatMoney(selectedTransfer.priceCents),
              quantity: _transferQty,
              onChanged: (value) {
                _updateStateAndSave(() {
                  _transferQty = value.clamp(1, 20).toInt();
                  _promoResult = null;
                });
              },
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '3) Промокод',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Введите промокод',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _validatingPromo ? null : _validatePromo,
                child: Text(_validatingPromo ? '...' : 'Применить'),
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
                    ? colorScheme.tertiary
                    : colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '4) Выберите способ оплаты',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (availablePaymentMethods.isEmpty)
            const _InfoCard(
              text:
                  'Способы оплаты временно скрыты администратором. Попробуйте позже.',
            )
          else
            ...availablePaymentMethods.map(
              (method) => _PaymentMethodTile(
                title: _paymentLabel(method),
                subtitle: _paymentSubtitle(method),
                selected: _paymentMethod == method,
                onTap: () => _updateStateAndSave(() => _paymentMethod = method),
              ),
            ),
          if (availablePaymentMethods.isNotEmpty)
            PaymentMethodPage(
              method: _paymentMethod,
              amountCents: _totalCents,
            ),
          const SizedBox(height: 16),
          Text(
            '5) Итог заказа',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
              label: 'Tickets + transfer', value: formatMoney(_subtotalCents)),
          _SummaryRow(
              label: 'Discount', value: '- ${formatMoney(_discountCents)}'),
          const Divider(),
          _SummaryRow(
            label: 'К оплате',
            value: formatMoney(_totalCents),
            emphasized: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ||
                    !_hasSelectedTickets ||
                    availablePaymentMethods.isEmpty
                ? null
                : _openPaymentCheckout,
            child: const Text('Перейти к оплате'),
          ),
          const SizedBox(height: 10),
          Text(
            !_hasSelectedTickets
                ? 'Сначала выберите хотя бы один билет.'
                : availablePaymentMethods.isEmpty
                    ? 'Сейчас нет доступных способов оплаты для этого события.'
                    : 'На следующем шаге вы увидите реквизиты и кнопку «Я оплатил(а)».',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'USDT':
        return 'Оплата USDT';
      case 'PAYMENT_QR':
        return 'Оплата по QR';
      case 'TOCHKA_SBP_QR':
        return 'SBP QR (Tochka)';
      case 'PHONE':
      default:
        return 'Перевод по номеру';
    }
  }

  String _paymentSubtitle(String method) {
    final custom = _paymentSettings?.descriptionForMethod(method).trim() ?? '';
    if (custom.isNotEmpty) return custom;
    switch (method) {
      case 'USDT':
        return 'Кошелек + сеть + сумма';
      case 'PAYMENT_QR':
        return 'Сканируете QR платежа';
      case 'TOCHKA_SBP_QR':
        return 'Динамический QR СБП';
      case 'PHONE':
      default:
        return 'Ручной перевод по номеру';
    }
  }

  TransferProductModel? _selectedTransfer(EventProductsModel products) {
    final selectedId = _selectedTransferId;
    if ((selectedId ?? '').trim().isEmpty) return null;
    for (final item in products.transfers) {
      if (!item.isActive) continue;
      if (item.id == selectedId) return item;
    }
    return null;
  }

  List<TransferProductModel> _activeTransfers(EventProductsModel products) {
    return products.transfers.where((item) => item.isActive).toList();
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
    } else if (method == 'TOCHKA_SBP_QR') {
      hint = 'A dynamic SBP QR from Tochka will be generated for this order.';
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
              color: statusTint(order.status, context),
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

class SbpQrPaymentPage extends ConsumerStatefulWidget {
  const SbpQrPaymentPage({
    required this.created,
    required this.onClose,
    super.key,
  });

  final CreateSbpQrOrderResponseModel created;
  final VoidCallback onClose;

  @override
  ConsumerState<SbpQrPaymentPage> createState() => _SbpQrPaymentPageState();
}

class _SbpQrPaymentPageState extends ConsumerState<SbpQrPaymentPage> {
  Timer? _timer;
  SbpQrStatusResponseModel? _status;
  String? _error;
  bool _loading = false;
  int _attempt = 0;
  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    unawaited(_pollStatus(scheduleNext: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _token =>
      ref.read(authControllerProvider).state.token?.trim() ?? '';

  bool get _isPollingExpired {
    return DateTime.now().difference(_startedAt) >= const Duration(minutes: 15);
  }

  Future<void> _pollStatus({bool scheduleNext = false}) async {
    final token = _token;
    if (token.isEmpty) {
      if (!mounted) return;
      setState(() => _error = 'Authorization required');
      return;
    }
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ref.read(ticketingRepositoryProvider).getSbpQrStatus(
            token: token,
            orderId: widget.created.order.order.id,
          );
      if (!mounted) return;
      setState(() => _status = result);
      if (_isPaid(result)) {
        _timer?.cancel();
        return;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    if (scheduleNext) {
      _scheduleNextPoll();
    }
  }

  void _scheduleNextPoll() {
    _timer?.cancel();
    if (!mounted || _isPollingExpired || _isPaid(_status)) return;
    final exp = min(_attempt, 4);
    final delaySeconds = min(15, 2 * (1 << exp));
    _attempt++;
    _timer = Timer(Duration(seconds: delaySeconds), () {
      unawaited(_pollStatus(scheduleNext: true));
    });
  }

  bool _isPaid(SbpQrStatusResponseModel? status) {
    if (status == null) return false;
    if (status.paid) return true;
    final orderStatus = status.orderStatus.toUpperCase();
    return orderStatus == 'PAID' ||
        orderStatus == 'REDEEMED' ||
        orderStatus == 'CONFIRMED';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detail = _status?.detail ?? widget.created.order;
    final order = detail.order;
    final paymentStatus = (_status?.paymentStatus.trim().isNotEmpty ?? false)
        ? _status!.paymentStatus
        : widget.created.sbpQr.status;
    final isPaid = _isPaid(_status) ||
        order.status.toUpperCase() == 'PAID' ||
        order.status.toUpperCase() == 'REDEEMED' ||
        order.status.toUpperCase() == 'CONFIRMED';
    final qrPayload = widget.created.sbpQr.payload.trim().isNotEmpty
        ? widget.created.sbpQr.payload.trim()
        : detail.paymentInstructions.paymentQrData.trim();
    final statusAccent = isPaid ? colorScheme.tertiary : colorScheme.primary;
    final statusBackgroundAlpha = isDark ? 0.28 : 0.14;
    final statusBorderAlpha = isDark ? 0.62 : 0.42;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Оплата СБП'),
        leading: IconButton(
          onPressed: widget.onClose,
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _loading
                ? null
                : () => unawaited(_pollStatus(scheduleNext: false)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusAccent.withValues(alpha: statusBackgroundAlpha),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusAccent.withValues(alpha: statusBorderAlpha),
              ),
            ),
            child: Row(
              children: [
                Icon(
                    isPaid
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    color: statusAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isPaid
                        ? 'Оплата подтверждена. Билет будет отправлен в Telegram-бот.'
                        : 'Ожидаем оплату через СБП. После оплаты статус обновится автоматически.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Order ID: ${order.id}'),
          Text('qrcId: ${widget.created.sbpQr.qrcId}'),
          Text('Сумма: ${formatMoney(order.totalCents)}'),
          Text('Order status: ${order.status}'),
          Text(
              'Payment status: ${paymentStatus.isEmpty ? 'PENDING' : paymentStatus}'),
          if ((_status?.message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_status!.message),
          ],
          if ((_error ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
          ],
          const SizedBox(height: 14),
          if (qrPayload.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outline),
                ),
                child: QrImageView(
                  data: qrPayload,
                  size: 260,
                  // White background improves scanner reliability in all themes.
                  backgroundColor: Colors.white,
                ),
              ),
            )
          else
            const _InfoCard(
                text:
                    'QR payload временно недоступен. Попробуйте обновить статус.'),
          const SizedBox(height: 10),
          if (qrPayload.isNotEmpty)
            SelectableText(qrPayload,
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading
                ? null
                : () => unawaited(_pollStatus(scheduleNext: false)),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_loading ? 'Проверка…' : 'Проверить оплату'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: widget.onClose,
            child: const Text('Закрыть'),
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
    final colorScheme = Theme.of(context).colorScheme;
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
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: quantity <= 0
                        ? null
                        : () => onChanged(max(0, quantity - 1)),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onChanged(quantity + 1),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outline,
              width: selected ? 1.6 : 1,
            ),
            color:
                selected ? colorScheme.primary.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline),
      ),
      child: Text(text),
    );
  }
}

class _PaymentCheckoutPage extends ConsumerWidget {
  const _PaymentCheckoutPage({
    required this.paymentMethod,
    required this.amountCents,
    required this.paymentSettings,
    required this.onBack,
    required this.onPaid,
    required this.submitting,
  });

  final String paymentMethod;
  final int amountCents;
  final PaymentSettingsModel? paymentSettings;
  final VoidCallback onBack;
  final VoidCallback? onPaid;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final config = ref.watch(appConfigProvider);
    final title = _methodTitle(paymentMethod);
    final customSubtitle = paymentSettings?.descriptionForMethod(paymentMethod);
    final subtitle = (customSubtitle ?? '').trim().isNotEmpty
        ? customSubtitle!.trim()
        : _methodSubtitle(paymentMethod);
    final phoneNumber = (paymentSettings?.phoneNumber ?? '').trim().isNotEmpty
        ? paymentSettings!.phoneNumber.trim()
        : config.paymentPhoneNumber;
    final usdtWallet = (paymentSettings?.usdtWallet ?? '').trim().isNotEmpty
        ? paymentSettings!.usdtWallet.trim()
        : config.paymentUsdtWallet;
    final usdtNetwork = (paymentSettings?.usdtNetwork ?? '').trim().isNotEmpty
        ? paymentSettings!.usdtNetwork.trim()
        : config.paymentUsdtNetwork;
    final usdtMemo = (paymentSettings?.usdtMemo ?? '').trim().isNotEmpty
        ? paymentSettings!.usdtMemo.trim()
        : config.paymentUsdtMemo;
    final paymentQrData =
        (paymentSettings?.paymentQrData ?? '').trim().isNotEmpty
            ? paymentSettings!.paymentQrData.trim()
            : config.paymentQrData;
    final isSbp = paymentMethod == 'TOCHKA_SBP_QR';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Реквизиты оплаты'),
        leading: IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Оплатите выбранным способом и подтвердите платеж.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outline),
              color: colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle),
                const SizedBox(height: 10),
                Text(
                  'Сумма к оплате: ${formatMoney(amountCents)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PaymentRequisitesBlock(
            paymentMethod: paymentMethod,
            phoneNumber: phoneNumber,
            usdtWallet: usdtWallet,
            usdtNetwork: usdtNetwork,
            usdtMemo: usdtMemo,
            qrData: paymentQrData,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onPaid,
            icon: Icon(isSbp
                ? Icons.qr_code_2_rounded
                : Icons.check_circle_outline_rounded),
            label: Text(
              submitting
                  ? (isSbp ? 'Создание…' : 'Отправка…')
                  : (isSbp ? 'Создать SBP QR' : 'Я оплатил(а)'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSbp
                ? 'После нажатия мы создадим динамический SBP QR и начнем автоматическую проверку оплаты.'
                : 'После нажатия будет создана заявка в статусе PENDING. Админ подтвердит или отклонит оплату.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onBack,
            child: const Text('Изменить заказ'),
          ),
        ],
      ),
    );
  }

  String _methodTitle(String method) {
    switch (method) {
      case 'USDT':
        return 'Оплата USDT';
      case 'PAYMENT_QR':
        return 'Оплата по QR коду';
      case 'TOCHKA_SBP_QR':
        return 'Оплата СБП через Точку';
      case 'PHONE':
      default:
        return 'Перевод по номеру телефона';
    }
  }

  String _methodSubtitle(String method) {
    switch (method) {
      case 'USDT':
        return 'Переведите точную сумму в USDT.';
      case 'PAYMENT_QR':
        return 'Сканируйте QR код или используйте payload ниже.';
      case 'TOCHKA_SBP_QR':
        return 'После создания заказа вы получите динамический QR СБП.';
      case 'PHONE':
      default:
        return 'Сделайте перевод на указанный номер.';
    }
  }
}

class _PaymentRequisitesBlock extends StatelessWidget {
  const _PaymentRequisitesBlock({
    required this.paymentMethod,
    required this.phoneNumber,
    required this.usdtWallet,
    required this.usdtNetwork,
    required this.usdtMemo,
    required this.qrData,
  });

  final String paymentMethod;
  final String phoneNumber;
  final String usdtWallet;
  final String usdtNetwork;
  final String usdtMemo;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    switch (paymentMethod) {
      case 'USDT':
        return _InfoCard(
          text: [
            'Кошелек: ${usdtWallet.trim().isEmpty ? 'не настроено' : usdtWallet}',
            'Сеть: ${usdtNetwork.trim().isEmpty ? 'TRC20' : usdtNetwork}',
            if (usdtMemo.trim().isNotEmpty) 'Memo/Tag: $usdtMemo',
          ].join('\n'),
        );
      case 'PAYMENT_QR':
        return _CopyDataCard(
          title: 'QR payload',
          value: qrData.trim().isEmpty
              ? 'QR payload не настроен. Укажите PAYMENT_QR_DATA.'
              : qrData,
        );
      case 'TOCHKA_SBP_QR':
        return const _InfoCard(
          text:
              'QR будет получен от Точки после создания заказа. Оплата проверяется автоматически.',
        );
      case 'PHONE':
      default:
        return _CopyDataCard(
          title: 'Номер для перевода',
          value: phoneNumber.trim().isEmpty
              ? 'Номер не настроен. Укажите PAYMENT_PHONE_NUMBER.'
              : phoneNumber,
        );
    }
  }
}

class _CopyDataCard extends StatelessWidget {
  const _CopyDataCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SelectableText(value),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скопировано')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Скопировать'),
          ),
        ],
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
