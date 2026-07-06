import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_time_utils.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/app_toast.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/admin_panel_background.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
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
  final TextEditingController _transferPaymentPhoneCtrl =
      TextEditingController();
  final TextEditingController _transferPaymentUsdtWalletCtrl =
      TextEditingController();
  final TextEditingController _transferPaymentUsdtNetworkCtrl =
      TextEditingController();
  final TextEditingController _transferPaymentUsdtMemoCtrl =
      TextEditingController();
  final TextEditingController _transferPaymentQrDataCtrl =
      TextEditingController();
  final TextEditingController _transferPhoneDescriptionCtrl =
      TextEditingController();
  final TextEditingController _transferUsdtDescriptionCtrl =
      TextEditingController();
  final TextEditingController _transferQrDescriptionCtrl =
      TextEditingController();
  final TextEditingController _transferSbpDescriptionCtrl =
      TextEditingController();
  final TextEditingController _ticketNameCtrl = TextEditingController();
  final TextEditingController _ticketPriceCtrl = TextEditingController();
  final TextEditingController _transferNameCtrl = TextEditingController();
  final TextEditingController _transferPriceCtrl = TextEditingController();
  final TextEditingController _transferTimeCtrl = TextEditingController();
  final TextEditingController _transferPickupCtrl = TextEditingController();
  final TextEditingController _transferArrivalCtrl = TextEditingController();
  final TextEditingController _transferCapacityCtrl = TextEditingController();
  final TextEditingController _transferNotesCtrl = TextEditingController();
  final TextEditingController _promoCodeCtrl = TextEditingController();
  final TextEditingController _promoValueCtrl = TextEditingController();
  final TextEditingController _promoUsageLimitCtrl = TextEditingController();

  String _ticketType = 'SINGLE';
  String _transferDirection = 'THERE';
  String _transferLandingKey = TransferProductModel.landingKeySpace;
  String _promoDiscountType = 'PERCENT';
  DateTime? _promoActiveFrom;
  DateTime? _promoActiveTo;
  bool _promoActiveOnly = false;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<TicketProductModel> _ticketProducts = <TicketProductModel>[];
  List<TransferProductModel> _transferProducts = <TransferProductModel>[];
  List<PromoCodeViewModel> _promoCodes = <PromoCodeViewModel>[];
  bool _phoneEnabled = true;
  bool _usdtEnabled = true;
  bool _paymentQrEnabled = true;
  bool _sbpEnabled = true;
  bool _transferPhoneEnabled = true;
  bool _transferUsdtEnabled = true;
  bool _transferPaymentQrEnabled = true;
  bool _transferSbpEnabled = true;

  bool get _isPercentPromoDiscount => _promoDiscountType == 'PERCENT';

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    if ((widget.initialEventId ?? 0) > 0) {
      _eventCtrl.text = '${widget.initialEventId}';
    }
    _paymentUsdtNetworkCtrl.text = 'TRC20';
    _transferPaymentUsdtNetworkCtrl.text = 'TRC20';
    _ticketPriceCtrl.text = '0';
    _transferPriceCtrl.text = '0';
    _transferCapacityCtrl.text = '53';
    _promoValueCtrl.text = '10';
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
    _transferPaymentPhoneCtrl.dispose();
    _transferPaymentUsdtWalletCtrl.dispose();
    _transferPaymentUsdtNetworkCtrl.dispose();
    _transferPaymentUsdtMemoCtrl.dispose();
    _transferPaymentQrDataCtrl.dispose();
    _transferPhoneDescriptionCtrl.dispose();
    _transferUsdtDescriptionCtrl.dispose();
    _transferQrDescriptionCtrl.dispose();
    _transferSbpDescriptionCtrl.dispose();
    _ticketNameCtrl.dispose();
    _ticketPriceCtrl.dispose();
    _transferNameCtrl.dispose();
    _transferPriceCtrl.dispose();
    _transferTimeCtrl.dispose();
    _transferPickupCtrl.dispose();
    _transferArrivalCtrl.dispose();
    _transferCapacityCtrl.dispose();
    _transferNotesCtrl.dispose();
    _promoCodeCtrl.dispose();
    _promoValueCtrl.dispose();
    _promoUsageLimitCtrl.dispose();
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
        repo.getAdminPaymentSettings(
          token: token,
          scope: PaymentSettingsScope.ticket,
        ),
        repo.getAdminPaymentSettings(
          token: token,
          scope: PaymentSettingsScope.transfer,
        ),
        repo.listAdminTicketProducts(
          token: token,
          eventId: (eventId ?? 0) > 0 ? eventId : null,
        ),
        repo.listAdminTransferProducts(
          token: token,
          eventId: (eventId ?? 0) > 0 ? eventId : null,
        ),
        repo.listAdminPromoCodes(
          token: token,
          eventId: (eventId ?? 0) > 0 ? eventId : null,
          active: _promoActiveOnly ? true : null,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _applyPaymentSettings(results[0] as PaymentSettingsModel);
        _applyTransferPaymentSettings(results[1] as PaymentSettingsModel);
        _ticketProducts = results[2] as List<TicketProductModel>;
        _transferProducts = results[3] as List<TransferProductModel>;
        _promoCodes = results[4] as List<PromoCodeViewModel>;
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
      await ref
          .read(ticketingRepositoryProvider)
          .createAdminTicketProduct(
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
    final capacityRaw = _transferCapacityCtrl.text.trim();
    final capacity = capacityRaw.isEmpty ? null : int.tryParse(capacityRaw);
    if (token.isEmpty || eventId <= 0 || price < 0) {
      _showMessage('Нужны ID события и корректная цена трансфера');
      return;
    }
    if (capacityRaw.isNotEmpty && (capacity == null || capacity <= 0)) {
      _showMessage('Вместимость должна быть положительным числом');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .createAdminTransferProduct(
            token: token,
            eventId: eventId,
            name: name,
            direction: _transferDirection,
            priceCents: price,
            info: <String, dynamic>{
              'landingKey': _transferLandingKey,
              'description': _transferNotesCtrl.text.trim(),
              'time': _transferTimeCtrl.text.trim(),
              'pickupPoint': _transferPickupCtrl.text.trim(),
              'arrivalPoint': _transferArrivalCtrl.text.trim(),
              'notes': _transferNotesCtrl.text.trim(),
            },
            inventoryLimit: capacity,
          );
      _showMessage('Трансферный продукт создан');
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _createPromoCode creates promo code.

  Future<void> _createPromoCode() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final code = _promoCodeCtrl.text.trim();
    final value = int.tryParse(_promoValueCtrl.text.trim());
    final usageLimitRaw = _promoUsageLimitCtrl.text.trim();
    final usageLimit =
        usageLimitRaw.isEmpty ? null : int.tryParse(usageLimitRaw);
    final eventIdRaw = _eventCtrl.text.trim();
    final eventId = eventIdRaw.isEmpty ? null : int.tryParse(eventIdRaw);

    if (token.isEmpty) {
      _showMessage('Требуется авторизация');
      return;
    }
    if (code.isEmpty) {
      _showMessage('Введите код промокода');
      return;
    }
    if (value == null || value <= 0) {
      _showMessage(
        _isPercentPromoDiscount
            ? 'Скидка в процентах должна быть больше 0'
            : 'Скидка в копейках должна быть больше 0',
      );
      return;
    }
    if (_isPercentPromoDiscount && value > 100) {
      _showMessage('Процент скидки не может быть больше 100');
      return;
    }
    if (usageLimitRaw.isNotEmpty && (usageLimit == null || usageLimit <= 0)) {
      _showMessage('Количество срабатываний должно быть больше 0');
      return;
    }
    if (eventIdRaw.isNotEmpty && (eventId == null || eventId <= 0)) {
      _showMessage('ID события должен быть положительным числом');
      return;
    }
    if (_promoActiveFrom != null &&
        _promoActiveTo != null &&
        !_promoActiveTo!.isAfter(_promoActiveFrom!)) {
      _showMessage('Окончание действия должно быть позже начала');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .createAdminPromoCode(
            token: token,
            code: code,
            discountType: _promoDiscountType,
            value: value,
            usageLimit: usageLimit,
            eventId: eventId,
            activeFrom: _promoActiveFrom?.toUtc().toIso8601String(),
            activeTo: _promoActiveTo?.toUtc().toIso8601String(),
            isActive: true,
          );
      _showMessage('Промокод создан');
      _promoCodeCtrl.clear();
      _promoUsageLimitCtrl.clear();
      _promoActiveFrom = null;
      _promoActiveTo = null;
      if (_isPercentPromoDiscount) {
        _promoValueCtrl.text = '10';
      }
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// _deletePromoCode deletes promo code.

  Future<void> _deletePromoCode(String id) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .deleteAdminPromoCode(token: token, promoId: id);
      _showMessage('Промокод удален');
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// _pickPromoActiveFrom handles pick promo active from.

  Future<void> _pickPromoActiveFrom() async {
    final initial = _promoActiveFrom ?? DateTime.now();
    final picked = await _pickPromoDateTime(initial: initial);
    if (picked == null || !mounted) return;
    setState(() {
      _promoActiveFrom = picked;
      if (_promoActiveTo != null && !_promoActiveTo!.isAfter(picked)) {
        _promoActiveTo = picked.add(const Duration(hours: 1));
      }
    });
  }

  /// _pickPromoActiveTo handles pick promo active to.

  Future<void> _pickPromoActiveTo() async {
    final initial = _promoActiveTo ?? _promoActiveFrom ?? DateTime.now();
    final picked = await _pickPromoDateTime(initial: initial);
    if (picked == null || !mounted) return;
    setState(() => _promoActiveTo = picked);
  }

  /// _pickPromoDateTime handles pick promo date time.

  Future<DateTime?> _pickPromoDateTime({required DateTime initial}) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5, 1, 1);
    final lastDate = DateTime(now.year + 10, 12, 31);
    final date = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: DateUtils.dateOnly(initial),
      helpText: 'Выберите дату',
      cancelText: 'Отмена',
      confirmText: 'Далее',
    );
    if (date == null || !mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Выберите время',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
      await ref
          .read(ticketingRepositoryProvider)
          .patchAdminTicketProduct(
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
    TransferProductModel item,
  ) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .patchAdminTransferProduct(
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

  /// _editTransferProduct updates editable transfer product fields.

  Future<void> _editTransferProduct(TransferProductModel item) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;

    final nameCtrl = TextEditingController(text: item.name);
    final priceCtrl = TextEditingController(text: '${item.priceCents}');
    final timeCtrl = TextEditingController(
      text: '${item.info['time'] ?? item.info['departureDatetime'] ?? ''}',
    );
    final pickupCtrl = TextEditingController(
      text: '${item.info['pickupPoint'] ?? item.info['departurePoint'] ?? ''}',
    );
    final arrivalCtrl = TextEditingController(
      text: '${item.info['arrivalPoint'] ?? ''}',
    );
    final descriptionCtrl = TextEditingController(
      text: '${item.info['description'] ?? item.info['notes'] ?? ''}',
    );
    final capacityCtrl = TextEditingController(
      text: item.inventoryLimit?.toString() ?? '53',
    );
    var editedLandingKey = item.landingKey;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Редактировать трансфер'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InputField(controller: nameCtrl, label: 'Название'),
                        const SizedBox(height: AppSpacing.xs),
                        DropdownButtonFormField<String>(
                          initialValue: editedLandingKey,
                          decoration: const InputDecoration(
                            labelText: 'Публичная страница',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: TransferProductModel.landingKeySpace,
                              child: Text('SPACE'),
                            ),
                            DropdownMenuItem(
                              value: TransferProductModel.landingKeyIskry,
                              child: Text('ISKRY'),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              editedLandingKey =
                                  value ?? TransferProductModel.landingKeySpace;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        InputField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          label: 'Цена в центах',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        InputField(
                          controller: capacityCtrl,
                          keyboardType: TextInputType.number,
                          label: 'Вместимость',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        InputField(
                          controller: timeCtrl,
                          label: 'Время отправления',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        InputField(
                          controller: pickupCtrl,
                          label: 'Точка посадки',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        InputField(
                          controller: arrivalCtrl,
                          label: 'Точка прибытия',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        InputField(
                          controller: descriptionCtrl,
                          label: 'Описание',
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Отмена'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
        );
      },
    );

    if (confirmed != true) {
      nameCtrl.dispose();
      priceCtrl.dispose();
      timeCtrl.dispose();
      pickupCtrl.dispose();
      arrivalCtrl.dispose();
      descriptionCtrl.dispose();
      capacityCtrl.dispose();
      return;
    }

    final editedName = nameCtrl.text.trim();
    final editedPriceRaw = priceCtrl.text.trim();
    final editedTime = timeCtrl.text.trim();
    final editedPickup = pickupCtrl.text.trim();
    final editedArrival = arrivalCtrl.text.trim();
    final editedDescription = descriptionCtrl.text.trim();
    final capacityRaw = capacityCtrl.text.trim();
    nameCtrl.dispose();
    priceCtrl.dispose();
    timeCtrl.dispose();
    pickupCtrl.dispose();
    arrivalCtrl.dispose();
    descriptionCtrl.dispose();
    capacityCtrl.dispose();

    final price = int.tryParse(editedPriceRaw);
    final capacity = capacityRaw.isEmpty ? null : int.tryParse(capacityRaw);
    if (price == null || price < 0) {
      _showMessage('Цена должна быть неотрицательным числом');
      return;
    }
    if (capacityRaw.isNotEmpty && (capacity == null || capacity <= 0)) {
      _showMessage('Вместимость должна быть положительным числом');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .patchAdminTransferProduct(
            token: token,
            productId: item.id,
            name: editedName,
            priceCents: price,
            inventoryLimit: capacity,
            info: <String, dynamic>{
              'landingKey': editedLandingKey,
              'description': editedDescription,
              'time': editedTime,
              'pickupPoint': editedPickup,
              'arrivalPoint': editedArrival,
              'notes': editedDescription,
            },
          );
      _showMessage('Трансфер обновлен');
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
            scope: PaymentSettingsScope.ticket,
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
      _showMessage('Платежные настройки билетов сохранены');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// _saveTransferPaymentSettings saves transfer payment settings.

  Future<void> _saveTransferPaymentSettings() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(ticketingRepositoryProvider)
          .upsertAdminPaymentSettings(
            token: token,
            scope: PaymentSettingsScope.transfer,
            phoneNumber: _transferPaymentPhoneCtrl.text,
            usdtWallet: _transferPaymentUsdtWalletCtrl.text,
            usdtNetwork: _transferPaymentUsdtNetworkCtrl.text,
            usdtMemo: _transferPaymentUsdtMemoCtrl.text,
            paymentQrData: _transferPaymentQrDataCtrl.text,
            phoneEnabled: _transferPhoneEnabled,
            usdtEnabled: _transferUsdtEnabled,
            paymentQrEnabled: _transferPaymentQrEnabled,
            sbpEnabled: _transferSbpEnabled,
            phoneDescription: _transferPhoneDescriptionCtrl.text,
            usdtDescription: _transferUsdtDescriptionCtrl.text,
            qrDescription: _transferQrDescriptionCtrl.text,
            sbpDescription: _transferSbpDescriptionCtrl.text,
          );
      if (!mounted) return;
      setState(() => _applyTransferPaymentSettings(saved));
      _showMessage('Платежные настройки трансферов сохранены');
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

    return AppScaffold(
      bodyBackground: const AdminPanelBackground(),
      appBar: AppBar(
        title: const Text('Админ-продукты'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      title: 'Продукты и платежи',
      subtitle: 'Управление билетами, трансферами и реквизитами',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.74),
      child: body,
    );
  }

  /// _buildBody builds body.

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: LoadingState(
          title: 'Загрузка продуктов',
          subtitle: 'Получаем платежные настройки и список продуктов',
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if ((_error ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ErrorState(message: _error!, onRetry: _load),
          ),
        _paymentSettingsSection(
          title: 'Платежные настройки билетов',
          subtitle: 'Отдельные методы оплаты для билетов на событие',
          phoneEnabled: _phoneEnabled,
          usdtEnabled: _usdtEnabled,
          paymentQrEnabled: _paymentQrEnabled,
          sbpEnabled: _sbpEnabled,
          onPhoneEnabledChanged:
              (value) => setState(() => _phoneEnabled = value),
          onUsdtEnabledChanged: (value) => setState(() => _usdtEnabled = value),
          onPaymentQrEnabledChanged:
              (value) => setState(() => _paymentQrEnabled = value),
          onSbpEnabledChanged: (value) => setState(() => _sbpEnabled = value),
          phoneCtrl: _paymentPhoneCtrl,
          usdtWalletCtrl: _paymentUsdtWalletCtrl,
          usdtNetworkCtrl: _paymentUsdtNetworkCtrl,
          usdtMemoCtrl: _paymentUsdtMemoCtrl,
          paymentQrDataCtrl: _paymentQrDataCtrl,
          phoneDescriptionCtrl: _phoneDescriptionCtrl,
          usdtDescriptionCtrl: _usdtDescriptionCtrl,
          qrDescriptionCtrl: _qrDescriptionCtrl,
          sbpDescriptionCtrl: _sbpDescriptionCtrl,
          onSave: _savePaymentSettings,
        ),
        const SizedBox(height: AppSpacing.sm),
        _paymentSettingsSection(
          title: 'Платежные настройки трансферов',
          subtitle: 'Отдельные методы оплаты только для трансферных продуктов',
          phoneEnabled: _transferPhoneEnabled,
          usdtEnabled: _transferUsdtEnabled,
          paymentQrEnabled: _transferPaymentQrEnabled,
          sbpEnabled: _transferSbpEnabled,
          onPhoneEnabledChanged:
              (value) => setState(() => _transferPhoneEnabled = value),
          onUsdtEnabledChanged:
              (value) => setState(() => _transferUsdtEnabled = value),
          onPaymentQrEnabledChanged:
              (value) => setState(() => _transferPaymentQrEnabled = value),
          onSbpEnabledChanged:
              (value) => setState(() => _transferSbpEnabled = value),
          phoneCtrl: _transferPaymentPhoneCtrl,
          usdtWalletCtrl: _transferPaymentUsdtWalletCtrl,
          usdtNetworkCtrl: _transferPaymentUsdtNetworkCtrl,
          usdtMemoCtrl: _transferPaymentUsdtMemoCtrl,
          paymentQrDataCtrl: _transferPaymentQrDataCtrl,
          phoneDescriptionCtrl: _transferPhoneDescriptionCtrl,
          usdtDescriptionCtrl: _transferUsdtDescriptionCtrl,
          qrDescriptionCtrl: _transferQrDescriptionCtrl,
          sbpDescriptionCtrl: _transferSbpDescriptionCtrl,
          onSave: _saveTransferPaymentSettings,
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Фильтр события',
          subtitle: 'ID события обязателен для создания продуктов',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputField(
                controller: _eventCtrl,
                keyboardType: TextInputType.number,
                label: 'ID события',
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Где взять ID: вкладка Парсер после импорта (событие #ID), список на вкладке Лендинг (#ID), либо URL события /space_app/events/<id>.',
              ),
              const SizedBox(height: AppSpacing.xs),
              SecondaryButton(
                onPressed: _load,
                label: 'Применить фильтр события',
                outline: true,
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Создать промокод',
          subtitle: 'Скидка, лимит срабатываний и период действия',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputField(
                      controller: _promoCodeCtrl,
                      label: 'Код промокода',
                      hint: 'Например SPRING25',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // Keep `value` for compatibility with older Flutter SDKs used in CI/Docker.
                      // ignore: deprecated_member_use
                      value: _promoDiscountType,
                      items: const [
                        DropdownMenuItem(
                          value: 'PERCENT',
                          child: Text('Процент (%)'),
                        ),
                        DropdownMenuItem(
                          value: 'FIXED',
                          child: Text('Фикс (копейки)'),
                        ),
                      ],
                      onChanged:
                          _busy
                              ? null
                              : (value) => setState(
                                () => _promoDiscountType = value ?? 'PERCENT',
                              ),
                      decoration: const InputDecoration(
                        labelText: 'Тип скидки',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: InputField(
                      controller: _promoValueCtrl,
                      keyboardType: TextInputType.number,
                      label:
                          _isPercentPromoDiscount
                              ? 'Скидка (%)'
                              : 'Скидка (копейки)',
                      hint:
                          _isPercentPromoDiscount
                              ? 'от 1 до 100'
                              : 'например 1500 = 15 RUB',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InputField(
                      controller: _promoUsageLimitCtrl,
                      keyboardType: TextInputType.number,
                      label: 'Количество срабатываний',
                      hint: 'Пусто = без лимита',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _DateSelectorField(
                label: 'Начало действия',
                value: _promoActiveFrom,
                onSelect: _pickPromoActiveFrom,
                onClear:
                    _promoActiveFrom == null
                        ? null
                        : () => setState(() => _promoActiveFrom = null),
              ),
              const SizedBox(height: AppSpacing.xs),
              _DateSelectorField(
                label: 'Окончание действия',
                value: _promoActiveTo,
                onSelect: _pickPromoActiveTo,
                onClear:
                    _promoActiveTo == null
                        ? null
                        : () => setState(() => _promoActiveTo = null),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      onPressed: _busy ? null : _createPromoCode,
                      label: _busy ? 'Подождите…' : 'Создать промокод',
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _promoActiveOnly,
                          onChanged:
                              _busy
                                  ? null
                                  : (value) {
                                    setState(
                                      () => _promoActiveOnly = value ?? false,
                                    );
                                    unawaited(_load());
                                  },
                        ),
                        const Expanded(
                          child: Text('Показывать только активные'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Промокоды (${_promoCodes.length})',
          child:
              _promoCodes.isEmpty
                  ? const EmptyState(
                    title: 'Промокодов нет',
                    subtitle: 'Создайте первый промокод для текущего фильтра.',
                  )
                  : Column(
                    children: [
                      for (final item in _promoCodes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: AppCard(
                            variant: AppCardVariant.plain,
                            child: ListTile(
                              title: Text(
                                '${item.code} · ${_formatPromoDiscount(item)}',
                              ),
                              subtitle: Text(
                                'Срабатываний: ${item.usedCount}/${item.usageLimit ?? '∞'}\n'
                                'Период: ${_formatPromoDateRange(item.activeFrom, item.activeTo)}\n'
                                'Событие: ${item.eventId ?? 'ALL'} · Активен: ${item.isActive ? 'да' : 'нет'}',
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                onPressed:
                                    _busy
                                        ? null
                                        : () => _deletePromoCode(item.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Создать билетный продукт',
          child: Column(
            children: [
              InputField(
                controller: _ticketNameCtrl,
                label: 'Название продукта (кастом)',
                hint: 'Пример: VIP-билет',
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _ticketType,
                      items: const [
                        DropdownMenuItem(
                          value: 'SINGLE',
                          child: Text('SINGLE'),
                        ),
                        DropdownMenuItem(
                          value: 'GROUP2',
                          child: Text('GROUP2'),
                        ),
                        DropdownMenuItem(
                          value: 'GROUP10',
                          child: Text('GROUP10'),
                        ),
                      ],
                      onChanged:
                          (value) =>
                              setState(() => _ticketType = value ?? 'SINGLE'),
                      decoration: const InputDecoration(labelText: 'Тип'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InputField(
                      controller: _ticketPriceCtrl,
                      keyboardType: TextInputType.number,
                      label: 'Цена в центах',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                onPressed: _busy ? null : _createTicketProduct,
                label: _busy ? 'Подождите…' : 'Создать билетный продукт',
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Создать трансферный продукт',
          child: Column(
            children: [
              InputField(
                controller: _transferNameCtrl,
                label: 'Название продукта (кастом)',
                hint: 'Пример: Трансфер до площадки',
              ),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _transferDirection,
                decoration: const InputDecoration(labelText: 'Направление'),
                items: const [
                  DropdownMenuItem(value: 'THERE', child: Text('THERE')),
                  DropdownMenuItem(value: 'BACK', child: Text('BACK')),
                  DropdownMenuItem(
                    value: 'ROUNDTRIP',
                    child: Text('ROUNDTRIP'),
                  ),
                ],
                onChanged:
                    (value) =>
                        setState(() => _transferDirection = value ?? 'THERE'),
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _transferPriceCtrl,
                keyboardType: TextInputType.number,
                label: 'Цена в центах',
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _transferTimeCtrl,
                label: 'Время трансфера',
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _transferPickupCtrl,
                label: 'Точка посадки',
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _transferArrivalCtrl,
                label: 'Точка прибытия',
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _transferCapacityCtrl,
                keyboardType: TextInputType.number,
                label: 'Вместимость',
                hint: 'По умолчанию 53',
              ),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String>(
                initialValue: _transferLandingKey,
                decoration: const InputDecoration(
                  labelText: 'Публичная страница',
                ),
                items: const [
                  DropdownMenuItem(
                    value: TransferProductModel.landingKeySpace,
                    child: Text('SPACE'),
                  ),
                  DropdownMenuItem(
                    value: TransferProductModel.landingKeyIskry,
                    child: Text('ISKRY'),
                  ),
                ],
                onChanged:
                    (value) => setState(
                      () =>
                          _transferLandingKey =
                              value ?? TransferProductModel.landingKeySpace,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _transferNotesCtrl,
                label: 'Описание / примечания',
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                onPressed: _busy ? null : _createTransferProduct,
                label: _busy ? 'Подождите…' : 'Создать трансферный продукт',
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Билетные продукты (${_ticketProducts.length})',
          child:
              _ticketProducts.isEmpty
                  ? const EmptyState(
                    title: 'Список пуст',
                    subtitle: 'Создайте первый билетный продукт для события.',
                  )
                  : Column(
                    children: [
                      for (final item in _ticketProducts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: AppCard(
                            variant: AppCardVariant.plain,
                            child: ListTile(
                              title: Text(
                                '${item.label} · ${formatMoney(item.priceCents)}',
                              ),
                              subtitle: Text(
                                'Event ${item.eventId} · code ${item.type} · sold ${item.soldCount} · ${item.isActive ? 'visible' : 'hidden'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed:
                                        _busy
                                            ? null
                                            : () =>
                                                _toggleTicketProductVisibility(
                                                  item,
                                                ),
                                    icon: Icon(
                                      item.isActive
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _busy
                                            ? null
                                            : () =>
                                                _deleteTicketProduct(item.id),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Трансферные продукты (${_transferProducts.length})',
          child:
              _transferProducts.isEmpty
                  ? const EmptyState(
                    title: 'Список пуст',
                    subtitle:
                        'Создайте первый трансферный продукт для события.',
                  )
                  : Column(
                    children: [
                      for (final item in _transferProducts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: AppCard(
                            variant: AppCardVariant.plain,
                            child: ListTile(
                              title: Text(
                                '${item.label} · ${formatMoney(item.priceCents)}',
                              ),
                              subtitle: Text(
                                'Event ${item.eventId} · code ${item.direction} · '
                                'landing ${item.landingLabel} · '
                                'limit ${item.inventoryLimit?.toString() ?? 'not set'} · '
                                'sold ${item.soldCount} · ${item.infoLabel} · '
                                '${item.isActive ? 'visible' : 'hidden'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed:
                                        _busy
                                            ? null
                                            : () => _editTransferProduct(item),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _busy
                                            ? null
                                            : () =>
                                                _toggleTransferProductVisibility(
                                                  item,
                                                ),
                                    icon: Icon(
                                      item.isActive
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _busy
                                            ? null
                                            : () =>
                                                _deleteTransferProduct(item.id),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
        ),
      ],
    );
  }

  /// _paymentSettingsSection renders one scoped payment settings form.

  Widget _paymentSettingsSection({
    required String title,
    required String subtitle,
    required bool phoneEnabled,
    required bool usdtEnabled,
    required bool paymentQrEnabled,
    required bool sbpEnabled,
    required ValueChanged<bool> onPhoneEnabledChanged,
    required ValueChanged<bool> onUsdtEnabledChanged,
    required ValueChanged<bool> onPaymentQrEnabledChanged,
    required ValueChanged<bool> onSbpEnabledChanged,
    required TextEditingController phoneCtrl,
    required TextEditingController usdtWalletCtrl,
    required TextEditingController usdtNetworkCtrl,
    required TextEditingController usdtMemoCtrl,
    required TextEditingController paymentQrDataCtrl,
    required TextEditingController phoneDescriptionCtrl,
    required TextEditingController usdtDescriptionCtrl,
    required TextEditingController qrDescriptionCtrl,
    required TextEditingController sbpDescriptionCtrl,
    required Future<void> Function() onSave,
  }) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: phoneEnabled,
            title: const Text('Показывать оплату по номеру'),
            onChanged: _busy ? null : onPhoneEnabledChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: usdtEnabled,
            title: const Text('Показывать оплату USDT'),
            onChanged: _busy ? null : onUsdtEnabledChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: paymentQrEnabled,
            title: const Text('Показывать оплату по QR'),
            onChanged: _busy ? null : onPaymentQrEnabledChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: sbpEnabled,
            title: const Text('Показывать оплату СБП (Точка)'),
            onChanged: _busy ? null : onSbpEnabledChanged,
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(controller: phoneCtrl, label: 'PAYMENT_PHONE_NUMBER'),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: usdtWalletCtrl,
            label: 'USDT TRC wallet',
            hint: 'Адрес кошелька TRC20',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: usdtNetworkCtrl,
            label: 'USDT network',
            hint: 'TRC20',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: usdtMemoCtrl,
            label: 'USDT memo/tag (optional)',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: paymentQrDataCtrl,
            minLines: 2,
            maxLines: 4,
            label: 'PAYMENT_QR_DATA',
            hint: 'order:{order_id};event:{event_id};amount:{amount}',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: phoneDescriptionCtrl,
            minLines: 2,
            maxLines: 4,
            label: 'Описание для оплаты по телефону',
            hint:
                'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: usdtDescriptionCtrl,
            minLines: 2,
            maxLines: 4,
            label: 'Описание для оплаты USDT',
            hint:
                'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: qrDescriptionCtrl,
            minLines: 2,
            maxLines: 4,
            label: 'Описание для PAYMENT_QR',
            hint:
                'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
          ),
          const SizedBox(height: AppSpacing.xs),
          InputField(
            controller: sbpDescriptionCtrl,
            minLines: 2,
            maxLines: 4,
            label: 'Описание для TOCHKA_SBP_QR',
            hint:
                'Плейсхолдеры: {amount}, {order_id}, {event_id}, {amount_cents}',
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            onPressed: _busy ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: _busy ? 'Подождите…' : 'Сохранить настройки',
            expand: true,
          ),
        ],
      ),
    );
  }

  /// _formatPromoDiscount formats promo discount.

  String _formatPromoDiscount(PromoCodeViewModel item) {
    if (item.discountType == 'FIXED') {
      return formatMoney(item.value);
    }
    return '${item.value}%';
  }

  /// _formatPromoDateRange formats promo date range.

  String _formatPromoDateRange(DateTime? from, DateTime? to) {
    final fromText = from == null ? 'без даты начала' : formatDateTime(from);
    final toText = to == null ? 'без даты окончания' : formatDateTime(to);
    return '$fromText — $toText';
  }

  /// _showMessage handles show message.

  void _showMessage(String message) {
    if (!mounted) return;
    AppToast.show(context, message: message);
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

  /// _applyTransferPaymentSettings applies transfer payment settings.

  void _applyTransferPaymentSettings(PaymentSettingsModel settings) {
    _transferPaymentPhoneCtrl.text = settings.phoneNumber;
    _transferPaymentUsdtWalletCtrl.text = settings.usdtWallet;
    _transferPaymentUsdtNetworkCtrl.text =
        settings.usdtNetwork.trim().isEmpty ? 'TRC20' : settings.usdtNetwork;
    _transferPaymentUsdtMemoCtrl.text = settings.usdtMemo;
    _transferPaymentQrDataCtrl.text = settings.paymentQrData;
    _transferPhoneEnabled = settings.phoneEnabled;
    _transferUsdtEnabled = settings.usdtEnabled;
    _transferPaymentQrEnabled = settings.paymentQrEnabled;
    _transferSbpEnabled = settings.sbpEnabled;
    _transferPhoneDescriptionCtrl.text = settings.phoneDescription;
    _transferUsdtDescriptionCtrl.text = settings.usdtDescription;
    _transferQrDescriptionCtrl.text = settings.qrDescription;
    _transferSbpDescriptionCtrl.text = settings.sbpDescription;
  }
}

/// _DateSelectorField represents date selector field.

class _DateSelectorField extends StatelessWidget {
  /// _DateSelectorField handles date selector field.
  const _DateSelectorField({
    required this.label,
    required this.value,
    required this.onSelect,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onSelect;
  final VoidCallback? onClear;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final text = value == null ? 'Без ограничения' : formatDateTime(value);

    return AppCard(
      variant: AppCardVariant.plain,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            onPressed: onSelect,
            icon: const Icon(Icons.edit_calendar_outlined),
            tooltip: 'Выбрать дату и время',
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded),
            tooltip: 'Очистить',
          ),
        ],
      ),
    );
  }
}
