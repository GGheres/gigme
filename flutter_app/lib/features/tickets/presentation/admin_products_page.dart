import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminProductsPage represents admin products page.

class AdminProductsPage extends ConsumerStatefulWidget {
  /// AdminProductsPage handles admin products page.
  const AdminProductsPage({
    super.key,
    this.embedded = false,
    this.initialEventId,
  });

  final bool embedded;
  final int? initialEventId;

  /// createState creates state.

  @override
  ConsumerState<AdminProductsPage> createState() => _AdminProductsPageState();
}

/// _AdminProductsPageState represents admin products page state.

class _AdminProductsPageState extends ConsumerState<AdminProductsPage> {
  final TextEditingController _eventCtrl = TextEditingController();
  final TextEditingController _paymentPhoneCtrl = TextEditingController();
  final TextEditingController _paymentUsdtWalletCtrl = TextEditingController();
  final TextEditingController _paymentUsdtNetworkCtrl = TextEditingController();
  final TextEditingController _paymentUsdtMemoCtrl = TextEditingController();
  final TextEditingController _paymentQrDataCtrl = TextEditingController();
  final TextEditingController _phoneDescriptionCtrl = TextEditingController();
  final TextEditingController _usdtDescriptionCtrl = TextEditingController();
  final TextEditingController _qrDescriptionCtrl = TextEditingController();
  final TextEditingController _sbpDescriptionCtrl = TextEditingController();
  final TextEditingController _ticketNameCtrl = TextEditingController();
  final TextEditingController _ticketPriceCtrl = TextEditingController();
  final TextEditingController _transferNameCtrl = TextEditingController();
  final TextEditingController _transferPriceCtrl = TextEditingController();
  final TextEditingController _transferTimeCtrl = TextEditingController();
  final TextEditingController _transferPickupCtrl = TextEditingController();
  final TextEditingController _transferNotesCtrl = TextEditingController();

  String _ticketType = 'SINGLE';
  String _transferDirection = 'THERE';

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<TicketProductModel> _ticketProducts = <TicketProductModel>[];
  List<TransferProductModel> _transferProducts = <TransferProductModel>[];
  bool _phoneEnabled = true;
  bool _usdtEnabled = true;
  bool _paymentQrEnabled = true;
  bool _sbpEnabled = true;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    if ((widget.initialEventId ?? 0) > 0) {
      _eventCtrl.text = '${widget.initialEventId}';
    }
    _paymentUsdtNetworkCtrl.text = 'TRC20';
    _ticketPriceCtrl.text = '0';
    _transferPriceCtrl.text = '0';
    unawaited(_load());
  }

  /// dispose releases resources held by this instance.

  @override
  void dispose() {
    _eventCtrl.dispose();
    _paymentPhoneCtrl.dispose();
    _paymentUsdtWalletCtrl.dispose();
    _paymentUsdtNetworkCtrl.dispose();
    _paymentUsdtMemoCtrl.dispose();
    _paymentQrDataCtrl.dispose();
    _phoneDescriptionCtrl.dispose();
    _usdtDescriptionCtrl.dispose();
    _qrDescriptionCtrl.dispose();
    _sbpDescriptionCtrl.dispose();
    _ticketNameCtrl.dispose();
    _ticketPriceCtrl.dispose();
    _transferNameCtrl.dispose();
    _transferPriceCtrl.dispose();
    _transferTimeCtrl.dispose();
    _transferPickupCtrl.dispose();
    _transferNotesCtrl.dispose();
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
    final eventId = int.tryParse(_eventCtrl.text.trim());

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(ticketingRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.getAdminPaymentSettings(token: token),
        repo.listAdminTicketProducts(
            token: token, eventId: (eventId ?? 0) > 0 ? eventId : null),
        repo.listAdminTransferProducts(
            token: token, eventId: (eventId ?? 0) > 0 ? eventId : null),
      ]);
      if (!mounted) return;
      setState(() {
        _applyPaymentSettings(results[0] as PaymentSettingsModel);
        _ticketProducts = results[1] as List<TicketProductModel>;
        _transferProducts = results[2] as List<TransferProductModel>;
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

  /// _createTicketProduct creates ticket product.

  Future<void> _createTicketProduct() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final eventId = int.tryParse(_eventCtrl.text.trim()) ?? 0;
    final name = _ticketNameCtrl.text.trim();
    final price = int.tryParse(_ticketPriceCtrl.text.trim()) ?? -1;
    if (token.isEmpty || eventId <= 0 || price < 0) {
      _showMessage('Нужны ID события и корректная цена билета');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).createAdminTicketProduct(
            token: token,
            eventId: eventId,
            name: name,
            type: _ticketType,
            priceCents: price,
          );
      _showMessage('Билетный продукт создан');
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _createTransferProduct creates transfer product.

  Future<void> _createTransferProduct() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final eventId = int.tryParse(_eventCtrl.text.trim()) ?? 0;
    final name = _transferNameCtrl.text.trim();
    final price = int.tryParse(_transferPriceCtrl.text.trim()) ?? -1;
    if (token.isEmpty || eventId <= 0 || price < 0) {
      _showMessage('Нужны ID события и корректная цена трансфера');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).createAdminTransferProduct(
        token: token,
        eventId: eventId,
        name: name,
        direction: _transferDirection,
        priceCents: price,
        info: <String, dynamic>{
          'time': _transferTimeCtrl.text.trim(),
          'pickupPoint': _transferPickupCtrl.text.trim(),
          'notes': _transferNotesCtrl.text.trim(),
        },
      );
      _showMessage('Трансферный продукт создан');
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _deleteTicketProduct deletes ticket product.

  Future<void> _deleteTicketProduct(String id) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .deleteAdminTicketProduct(token: token, productId: id);
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _deleteTransferProduct deletes transfer product.

  Future<void> _deleteTransferProduct(String id) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .deleteAdminTransferProduct(token: token, productId: id);
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _toggleTicketProductVisibility handles toggle ticket product visibility.

  Future<void> _toggleTicketProductVisibility(TicketProductModel item) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).patchAdminTicketProduct(
            token: token,
            productId: item.id,
            isActive: !item.isActive,
          );
      _showMessage(
        !item.isActive
            ? 'Билетный продукт снова в показе'
            : 'Билетный продукт скрыт',
      );
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _toggleTransferProductVisibility handles toggle transfer product visibility.

  Future<void> _toggleTransferProductVisibility(
      TransferProductModel item) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).patchAdminTransferProduct(
            token: token,
            productId: item.id,
            isActive: !item.isActive,
          );
      _showMessage(
        !item.isActive
            ? 'Трансферный продукт снова в показе'
            : 'Трансферный продукт скрыт',
      );
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _savePaymentSettings saves payment settings.

  Future<void> _savePaymentSettings() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(ticketingRepositoryProvider)
          .upsertAdminPaymentSettings(
            token: token,
            phoneNumber: _paymentPhoneCtrl.text,
            usdtWallet: _paymentUsdtWalletCtrl.text,
            usdtNetwork: _paymentUsdtNetworkCtrl.text,
            usdtMemo: _paymentUsdtMemoCtrl.text,
            paymentQrData: _paymentQrDataCtrl.text,
            phoneEnabled: _phoneEnabled,
            usdtEnabled: _usdtEnabled,
            paymentQrEnabled: _paymentQrEnabled,
            sbpEnabled: _sbpEnabled,
            phoneDescription: _phoneDescriptionCtrl.text,
            usdtDescription: _usdtDescriptionCtrl.text,
            qrDescription: _qrDescriptionCtrl.text,
            sbpDescription: _sbpDescriptionCtrl.text,
          );
      if (!mounted) return;
      setState(() => _applyPaymentSettings(saved));
      _showMessage('Платежные настройки сохранены');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-продукты'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: body,
    );
  }

  /// _buildBody builds body.

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if ((_error ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Платежные настройки',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _phoneEnabled,
                  title: const Text('Показывать оплату по номеру'),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _phoneEnabled = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _usdtEnabled,
                  title: const Text('Показывать оплату USDT'),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _usdtEnabled = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _paymentQrEnabled,
                  title: const Text('Показывать оплату по QR'),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _paymentQrEnabled = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _sbpEnabled,
                  title: const Text('Показывать оплату СБП (Точка)'),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _sbpEnabled = value),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _paymentPhoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'PAYMENT_PHONE_NUMBER',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentUsdtWalletCtrl,
                  decoration: const InputDecoration(
                    labelText: 'USDT TRC wallet',
                    hintText: 'Адрес кошелька TRC20',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentUsdtNetworkCtrl,
                  decoration: const InputDecoration(
                    labelText: 'USDT network',
                    hintText: 'TRC20',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentUsdtMemoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'USDT memo/tag (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentQrDataCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'PAYMENT_QR_DATA',
                    hintText:
                        'order:{order_id};event:{event_id};amount:{amount}',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneDescriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Описание для оплаты по телефону',
                    hintText:
                        'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usdtDescriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Описание для оплаты USDT',
                    hintText:
                        'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _qrDescriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Описание для PAYMENT_QR',
                    hintText:
                        'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sbpDescriptionCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Описание для TOCHKA_SBP_QR',
                    hintText:
                        'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _savePaymentSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                      _busy ? 'Подождите…' : 'Сохранить платежные настройки'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _eventCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'ID события (обязателен для создания/фильтрации)',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Где взять ID события: вкладка Парсер после импорта (событие #ID), список на вкладке Лендинг (#ID), либо URL события /space_app/events/<id>.',
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: _load,
          child: const Text('Применить фильтр события'),
        ),
        const SizedBox(height: 14),
        Text(
          'Создать билетный продукт',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ticketNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Название продукта (кастом)',
            hintText: 'Пример: VIP-билет',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _ticketType,
                items: const [
                  DropdownMenuItem(value: 'SINGLE', child: Text('SINGLE')),
                  DropdownMenuItem(value: 'GROUP2', child: Text('GROUP2')),
                  DropdownMenuItem(value: 'GROUP10', child: Text('GROUP10')),
                ],
                onChanged: (value) =>
                    setState(() => _ticketType = value ?? 'SINGLE'),
                decoration: const InputDecoration(labelText: 'Тип'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ticketPriceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Цена в центах'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _createTicketProduct,
          child: Text(_busy ? 'Подождите…' : 'Создать билетный продукт'),
        ),
        const SizedBox(height: 14),
        Text(
          'Создать трансферный продукт',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _transferNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Название продукта (кастом)',
            hintText: 'Пример: Трансфер до площадки',
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _transferDirection,
          decoration: const InputDecoration(labelText: 'Направление'),
          items: const [
            DropdownMenuItem(value: 'THERE', child: Text('THERE')),
            DropdownMenuItem(value: 'BACK', child: Text('BACK')),
            DropdownMenuItem(value: 'ROUNDTRIP', child: Text('ROUNDTRIP')),
          ],
          onChanged: (value) =>
              setState(() => _transferDirection = value ?? 'THERE'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _transferPriceCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Цена в центах'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _transferTimeCtrl,
          decoration: const InputDecoration(labelText: 'Время трансфера'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _transferPickupCtrl,
          decoration: const InputDecoration(labelText: 'Точка посадки'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _transferNotesCtrl,
          decoration: const InputDecoration(labelText: 'Примечания'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _createTransferProduct,
          child: Text(_busy ? 'Подождите…' : 'Создать трансферный продукт'),
        ),
        const SizedBox(height: 16),
        Text(
          'Билетные продукты (${_ticketProducts.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ..._ticketProducts.map(
          (item) => Card(
            child: ListTile(
              title: Text('${item.label} · ${formatMoney(item.priceCents)}'),
              subtitle: Text(
                'Event ${item.eventId} · code ${item.type} · sold ${item.soldCount} · ${item.isActive ? 'visible' : 'hidden'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => _toggleTicketProductVisibility(item),
                    icon: Icon(
                      item.isActive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _busy ? null : () => _deleteTicketProduct(item.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Трансферные продукты (${_transferProducts.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ..._transferProducts.map(
          (item) => Card(
            child: ListTile(
              title: Text('${item.label} · ${formatMoney(item.priceCents)}'),
              subtitle: Text(
                'Event ${item.eventId} · code ${item.direction} · ${item.infoLabel} · ${item.isActive ? 'visible' : 'hidden'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => _toggleTransferProductVisibility(item),
                    icon: Icon(
                      item.isActive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _busy ? null : () => _deleteTransferProduct(item.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// _showMessage handles show message.

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// _applyPaymentSettings handles apply payment settings.

  void _applyPaymentSettings(PaymentSettingsModel settings) {
    _paymentPhoneCtrl.text = settings.phoneNumber;
    _paymentUsdtWalletCtrl.text = settings.usdtWallet;
    _paymentUsdtNetworkCtrl.text =
        settings.usdtNetwork.trim().isEmpty ? 'TRC20' : settings.usdtNetwork;
    _paymentUsdtMemoCtrl.text = settings.usdtMemo;
    _paymentQrDataCtrl.text = settings.paymentQrData;
    _phoneEnabled = settings.phoneEnabled;
    _usdtEnabled = settings.usdtEnabled;
    _paymentQrEnabled = settings.paymentQrEnabled;
    _sbpEnabled = settings.sbpEnabled;
    _phoneDescriptionCtrl.text = settings.phoneDescription;
    _usdtDescriptionCtrl.text = settings.usdtDescription;
    _qrDescriptionCtrl.text = settings.qrDescription;
    _sbpDescriptionCtrl.text = settings.sbpDescription;
  }
}
