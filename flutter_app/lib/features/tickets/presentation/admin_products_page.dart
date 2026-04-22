import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/admin_filter_bar.dart';
import '../../../ui/components/admin_form_section.dart';
import '../../../ui/components/admin_list_item.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

class AdminProductsPage extends ConsumerStatefulWidget {
  const AdminProductsPage({
    super.key,
    this.embedded = false,
    this.initialEventId,
  });

  final bool embedded;
  final int? initialEventId;

  @override
  ConsumerState<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends ConsumerState<AdminProductsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if ((widget.initialEventId ?? 0) > 0) {
      _eventCtrl.text = '${widget.initialEventId}';
    }
    _paymentUsdtNetworkCtrl.text = 'TRC20';
    _ticketPriceCtrl.text = '0';
    _transferPriceCtrl.text = '0';
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      _ticketNameCtrl.clear();
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      _transferNameCtrl.clear();
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-продукты'),
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

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final activeTickets =
        _ticketProducts.where((p) => p.isActive).length;
    final activeTransfers =
        _transferProducts.where((p) => p.isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHero(
          title: 'Продукты',
          subtitle:
              'Платежные настройки, билетные и трансферные продукты события',
          leadingIcon: Icons.inventory_2_outlined,
          metrics: [
            heroMetric('Билеты', '$activeTickets/${_ticketProducts.length}',
                icon: Icons.confirmation_number_outlined),
            heroMetric(
                'Трансферы', '$activeTransfers/${_transferProducts.length}',
                icon: Icons.directions_bus_outlined,
                accent: AppColors.info),
          ],
        ),
        AdminFilterBar(
          fields: [
            TextField(
              controller: _eventCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ID события',
                helperText:
                    'Нужен для создания и фильтрации списков',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              onSubmitted: (_) => _load(),
            ),
          ],
          actions: [
            FilledButton.icon(
              onPressed: _busy ? null : _load,
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
              title: 'Не удалось загрузить данные',
              message: _error!,
              onRetry: _load,
            ),
          ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.payments_outlined), text: 'Платежи'),
            Tab(
                icon: Icon(Icons.confirmation_number_outlined),
                text: 'Билеты'),
            Tab(
                icon: Icon(Icons.directions_bus_outlined),
                text: 'Трансферы'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPaymentsTab(),
              _buildTicketsTab(),
              _buildTransfersTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────── Payments tab ───────────

  Widget _buildPaymentsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        AdminFormSection(
          title: 'Активные методы оплаты',
          description: 'Тумблеры управляют отображением в интерфейсе покупки.',
          leadingIcon: Icons.toggle_on_outlined,
          children: [
            _paymentSwitch(
              label: 'Оплата по номеру телефона',
              value: _phoneEnabled,
              onChanged: (v) => setState(() => _phoneEnabled = v),
            ),
            _paymentSwitch(
              label: 'Оплата USDT',
              value: _usdtEnabled,
              onChanged: (v) => setState(() => _usdtEnabled = v),
            ),
            _paymentSwitch(
              label: 'Оплата по QR',
              value: _paymentQrEnabled,
              onChanged: (v) => setState(() => _paymentQrEnabled = v),
            ),
            _paymentSwitch(
              label: 'Оплата СБП (Точка)',
              value: _sbpEnabled,
              onChanged: (v) => setState(() => _sbpEnabled = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AdminFormSection(
          title: 'Реквизиты',
          leadingIcon: Icons.vpn_key_outlined,
          children: [
            TextField(
              controller: _paymentPhoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Номер телефона',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            TextField(
              controller: _paymentUsdtWalletCtrl,
              decoration: const InputDecoration(
                labelText: 'USDT кошелёк',
                hintText: 'Адрес кошелька',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            TextField(
              controller: _paymentUsdtNetworkCtrl,
              decoration: const InputDecoration(
                labelText: 'USDT network',
                hintText: 'TRC20',
                prefixIcon: Icon(Icons.lan_outlined),
              ),
            ),
            TextField(
              controller: _paymentUsdtMemoCtrl,
              decoration: const InputDecoration(
                labelText: 'USDT memo/tag (необязательно)',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
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
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AdminFormSection(
          title: 'Описания для пользователя',
          description:
              'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
          leadingIcon: Icons.text_snippet_outlined,
          children: [
            _multilineField(
                _phoneDescriptionCtrl, 'Описание для оплаты по телефону'),
            _multilineField(_usdtDescriptionCtrl, 'Описание для оплаты USDT'),
            _multilineField(_qrDescriptionCtrl, 'Описание для PAYMENT_QR'),
            _multilineField(_sbpDescriptionCtrl, 'Описание для TOCHKA_SBP_QR'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : _savePaymentSettings,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_busy ? 'Сохраняем…' : 'Сохранить платежные настройки'),
        ),
      ],
    );
  }

  Widget _paymentSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text(label),
      onChanged: _busy ? null : onChanged,
    );
  }

  Widget _multilineField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(labelText: label),
    );
  }

  // ─────────── Tickets tab ───────────

  Widget _buildTicketsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        AdminFormSection(
          title: 'Новый билетный продукт',
          description:
              'Для создания укажите ID события в фильтре сверху, название и цену в центах.',
          leadingIcon: Icons.add_circle_outline_rounded,
          children: [
            TextField(
              controller: _ticketNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название (кастом)',
                hintText: 'Пример: VIP-билет',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _ticketType,
                    items: const [
                      DropdownMenuItem(
                          value: 'SINGLE', child: Text('SINGLE')),
                      DropdownMenuItem(
                          value: 'GROUP2', child: Text('GROUP2')),
                      DropdownMenuItem(
                          value: 'GROUP10', child: Text('GROUP10')),
                    ],
                    onChanged: (value) =>
                        setState(() => _ticketType = value ?? 'SINGLE'),
                    decoration: const InputDecoration(labelText: 'Тип'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextField(
                    controller: _ticketPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Цена в центах',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _createTicketProduct,
                icon: const Icon(Icons.add_rounded),
                label: Text(_busy ? 'Создаём…' : 'Создать билетный продукт'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Билетные продукты · ${_ticketProducts.length}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_ticketProducts.isEmpty)
          const EmptyState(
            title: 'Билетных продуктов нет',
            subtitle: 'Создайте первый билетный продукт с помощью формы выше.',
            icon: Icons.confirmation_number_outlined,
          )
        else
          ..._ticketProducts.map(_buildTicketItem),
      ],
    );
  }

  Widget _buildTicketItem(TicketProductModel item) {
    final statusLabel = item.isActive ? 'VISIBLE' : 'HIDDEN';
    final statusColor =
        item.isActive ? AppColors.success : AppColors.textSecondary;

    return AdminListItem(
      title: item.label,
      subtitleLines: [
        'Event ${item.eventId} · ${item.type}',
        'Продано: ${item.soldCount}',
      ],
      trailingValue: formatMoney(item.priceCents),
      status: AdminListItemStatus(
        label: statusLabel,
        foreground: statusColor,
        tint: statusColor.withValues(alpha: 0.12),
      ),
      actions: [
        IconButton(
          tooltip: item.isActive ? 'Скрыть' : 'Показать',
          onPressed:
              _busy ? null : () => _toggleTicketProductVisibility(item),
          icon: Icon(
            item.isActive
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Удалить',
          onPressed: _busy ? null : () => _deleteTicketProduct(item.id),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  // ─────────── Transfers tab ───────────

  Widget _buildTransfersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        AdminFormSection(
          title: 'Новый трансферный продукт',
          description:
              'Укажите ID события, направление, цену и детали маршрута.',
          leadingIcon: Icons.add_circle_outline_rounded,
          children: [
            TextField(
              controller: _transferNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название (кастом)',
                hintText: 'Пример: Трансфер до площадки',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _transferDirection,
              decoration: const InputDecoration(
                labelText: 'Направление',
                prefixIcon: Icon(Icons.alt_route_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'THERE', child: Text('THERE')),
                DropdownMenuItem(value: 'BACK', child: Text('BACK')),
                DropdownMenuItem(
                    value: 'ROUNDTRIP', child: Text('ROUNDTRIP')),
              ],
              onChanged: (value) =>
                  setState(() => _transferDirection = value ?? 'THERE'),
            ),
            TextField(
              controller: _transferPriceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Цена в центах',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            TextField(
              controller: _transferTimeCtrl,
              decoration: const InputDecoration(
                labelText: 'Время трансфера',
                prefixIcon: Icon(Icons.schedule_rounded),
              ),
            ),
            TextField(
              controller: _transferPickupCtrl,
              decoration: const InputDecoration(
                labelText: 'Точка посадки',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            TextField(
              controller: _transferNotesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Примечания',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _createTransferProduct,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                    _busy ? 'Создаём…' : 'Создать трансферный продукт'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Трансферные продукты · ${_transferProducts.length}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_transferProducts.isEmpty)
          const EmptyState(
            title: 'Трансферных продуктов нет',
            subtitle:
                'Создайте первый трансферный продукт с помощью формы выше.',
            icon: Icons.directions_bus_outlined,
          )
        else
          ..._transferProducts.map(_buildTransferItem),
      ],
    );
  }

  Widget _buildTransferItem(TransferProductModel item) {
    final statusLabel = item.isActive ? 'VISIBLE' : 'HIDDEN';
    final statusColor =
        item.isActive ? AppColors.success : AppColors.textSecondary;

    return AdminListItem(
      title: item.label,
      subtitleLines: [
        'Event ${item.eventId} · ${item.direction}',
        if (item.infoLabel.isNotEmpty) item.infoLabel,
      ],
      trailingValue: formatMoney(item.priceCents),
      status: AdminListItemStatus(
        label: statusLabel,
        foreground: statusColor,
        tint: statusColor.withValues(alpha: 0.12),
      ),
      actions: [
        IconButton(
          tooltip: item.isActive ? 'Скрыть' : 'Показать',
          onPressed:
              _busy ? null : () => _toggleTransferProductVisibility(item),
          icon: Icon(
            item.isActive
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
        IconButton(
          tooltip: 'Удалить',
          onPressed: _busy ? null : () => _deleteTransferProduct(item.id),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
