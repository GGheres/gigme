import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/components/sticky_action_bar.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../tickets/data/ticketing_repository.dart';
import '../../tickets/domain/ticketing_models.dart';
import '../../tickets/presentation/purchase_ticket_flow.dart';
import '../../tickets/presentation/ticketing_ui_utils.dart';
import '../data/iskry_repository.dart';
import '../domain/iskry_models.dart';

/// IskryLandingPage represents the public ISKRY transfer landing.
class IskryLandingPage extends ConsumerStatefulWidget {
  /// IskryLandingPage creates the public transfer landing.
  const IskryLandingPage({super.key});

  /// createState creates state.
  @override
  ConsumerState<IskryLandingPage> createState() => _IskryLandingPageState();
}

/// _IskryLandingPageState stores landing UI state.
class _IskryLandingPageState extends ConsumerState<IskryLandingPage> {
  static final RegExp _telegramUsernamePattern = RegExp(
    r'^[A-Za-z0-9_]{5,32}$',
  );

  final TextEditingController _telegramCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  IskryLandingModel? _landing;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _selectedProductId;
  int _quantity = 1;
  OrderDetailModel? _createdOrder;

  /// initState loads public landing data.
  @override
  void initState() {
    super.initState();
    _telegramCtrl.addListener(_onFormChanged);
    _nameCtrl.addListener(_onFormChanged);
    _phoneCtrl.addListener(_onFormChanged);
    unawaited(_loadLanding());
  }

  /// dispose releases field controllers.
  @override
  void dispose() {
    _telegramCtrl.removeListener(_onFormChanged);
    _nameCtrl.removeListener(_onFormChanged);
    _phoneCtrl.removeListener(_onFormChanged);
    _telegramCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// _onFormChanged refreshes derived button/validation state as the user types.
  void _onFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// _loadLanding fetches public ISKRY products.
  Future<void> _loadLanding() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final landing = await ref.read(iskryRepositoryProvider).getLanding();
      if (!mounted) return;
      setState(() {
        _landing = landing;
        _selectedProductId = _resolveInitialProductId(landing);
        _quantity = _clampQuantity(_selectedProduct, _quantity);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  /// _resolveInitialProductId chooses the first active product with seats, falling back to the first card.
  String? _resolveInitialProductId(IskryLandingModel landing) {
    for (final product in landing.products) {
      if (product.isActive && product.availableSeats > 0) {
        return product.id;
      }
    }
    if (landing.products.isEmpty) {
      return null;
    }
    return landing.products.first.id;
  }

  /// _selectedProduct returns the selected public transfer product.
  IskryTransferProductModel? get _selectedProduct {
    final landing = _landing;
    final selectedProductId = _selectedProductId?.trim();
    if (landing == null || (selectedProductId ?? '').isEmpty) {
      return null;
    }
    for (final product in landing.products) {
      if (product.id == selectedProductId) {
        return product;
      }
    }
    return null;
  }

  /// _maxSelectableSeats returns the backend-advertised seat ceiling for the selected product.
  int get _maxSelectableSeats {
    final product = _selectedProduct;
    if (product == null) return 0;
    return math.max(0, math.min(product.capacity, product.availableSeats));
  }

  /// _clampQuantity keeps quantity inside allowed bounds.
  int _clampQuantity(IskryTransferProductModel? product, int quantity) {
    if (product == null) return 1;
    final maxSeats = math.max(
      0,
      math.min(product.capacity, product.availableSeats),
    );
    if (maxSeats <= 0) {
      return 1;
    }
    return quantity.clamp(1, maxSeats).toInt();
  }

  /// _normalizedTelegram normalizes Telegram contact to @username for API calls.
  String? get _normalizedTelegram {
    final rawValue = _telegramCtrl.text.trim();
    if (rawValue.isEmpty) {
      return null;
    }

    var normalized = rawValue;
    if (normalized.startsWith('https://')) {
      normalized = normalized.substring('https://'.length);
    } else if (normalized.startsWith('http://')) {
      normalized = normalized.substring('http://'.length);
    }
    normalized = normalized.trim();
    if (normalized.startsWith('t.me/')) {
      normalized = normalized.substring('t.me/'.length);
    } else if (normalized.startsWith('telegram.me/')) {
      normalized = normalized.substring('telegram.me/'.length);
    }
    normalized = normalized.replaceFirst(RegExp(r'^@'), '').trim();
    normalized = normalized.replaceAll(RegExp(r'^/+|/+$'), '').trim();
    if (normalized.contains('/') || normalized.contains(RegExp(r'\s'))) {
      return null;
    }
    if (!_telegramUsernamePattern.hasMatch(normalized)) {
      return null;
    }
    return '@$normalized';
  }

  /// _telegramError returns inline validation for the Telegram field.
  String? get _telegramError {
    final rawValue = _telegramCtrl.text.trim();
    if (rawValue.isEmpty) {
      return 'Укажите Telegram username.';
    }
    if (_normalizedTelegram == null) {
      return 'Поддерживаются @username, username и ссылки t.me/username.';
    }
    return null;
  }

  /// _isAuthenticated reports whether the page has a valid auth session.
  bool get _isAuthenticated {
    final authState = ref.read(authControllerProvider).state;
    return authState.isAuthed && (authState.token ?? '').trim().isNotEmpty;
  }

  /// _token returns a trimmed auth token when available.
  String get _token =>
      ref.read(authControllerProvider).state.token?.trim() ?? '';

  /// _totalCents returns total price for the current selection.
  int get _totalCents {
    final product = _selectedProduct;
    if (product == null) return 0;
    return product.priceCents * _quantity;
  }

  /// _submit creates a regular order with phone payment instructions.
  Future<void> _submit() async {
    final landing = _landing;
    final product = _selectedProduct;
    final normalizedTelegram = _normalizedTelegram;
    if (landing == null || product == null) {
      _showMessage('Трансфер недоступен');
      return;
    }
    if (!_isAuthenticated) {
      _openAuth();
      return;
    }
    if ((normalizedTelegram ?? '').isEmpty) {
      _showMessage(_telegramError ?? 'Проверьте Telegram username');
      return;
    }
    if (_maxSelectableSeats <= 0) {
      _showMessage('Места закончились');
      return;
    }

    setState(() => _submitting = true);
    try {
      final created = await ref
          .read(ticketingRepositoryProvider)
          .createOrder(
            token: _token,
            payload: CreateOrderPayload(
              eventId: landing.eventId,
              contactTelegram: normalizedTelegram!,
              contactName: _nameCtrl.text.trim(),
              contactPhone: _phoneCtrl.text.trim(),
              paymentMethod: 'PHONE',
              paymentReference: '',
              ticketItems: const <OrderSelectionModel>[],
              transferItems: <OrderSelectionModel>[
                OrderSelectionModel(productId: product.id, quantity: _quantity),
              ],
              promoCode: '',
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

  /// _openAuth starts the login flow without leaving the user on SPACE auth screens.
  void _openAuth() {
    unawaited(_openAuthFlow());
  }

  /// _openAuthFlow authenticates the user and returns directly to /iskry when a helper is needed.
  Future<void> _openAuthFlow() async {
    final inlineInitData = _inlineTelegramInitData;
    if (inlineInitData.isNotEmpty) {
      final auth = ref.read(authControllerProvider);
      await auth.loginWithTelegram(inlineInitData);
      if (!mounted) return;
      final error = (auth.state.error ?? '').trim();
      if (auth.state.status != AuthStatus.authenticated && error.isNotEmpty) {
        _showMessage(error);
      }
      return;
    }

    final helperUri = _standaloneHelperUri();
    if (helperUri != null) {
      TelegramWebAppBridge.redirect(helperUri.toString());
      return;
    }

    final target =
        Uri(
          path: AppRoutes.auth,
          queryParameters: const <String, String>{'next': AppRoutes.iskry},
        ).toString();
    if (!mounted) return;
    context.go(target);
  }

  /// _inlineTelegramInitData reads Telegram initData when the current webview already exposes it.
  String get _inlineTelegramInitData =>
      TelegramWebAppBridge.getInitData()?.trim() ?? '';

  /// _standaloneHelperUri builds the helper URL that returns directly to the ISKRY landing.
  Uri? _standaloneHelperUri() {
    final rawHelperUrl = ref.read(appConfigProvider).standaloneAuthUrl.trim();
    if (rawHelperUrl.isEmpty) return null;

    final parsed = Uri.tryParse(rawHelperUrl);
    if (parsed == null) return null;

    final helperBase = parsed.hasScheme ? parsed : Uri.base.resolveUri(parsed);
    return helperBase.replace(
      queryParameters: <String, String>{
        ...helperBase.queryParameters,
        'redirect_uri': _iskryReturnUrl(),
      },
    );
  }

  /// _iskryReturnUrl builds the absolute URL used by the Telegram helper after successful login.
  String _iskryReturnUrl() {
    final base = Uri.base;
    final hasOrigin = base.scheme.isNotEmpty && base.host.isNotEmpty;
    final uri = Uri(
      scheme: hasOrigin ? base.scheme : 'https',
      host: hasOrigin ? base.host : 'spacefestival.fun',
      port: hasOrigin && base.hasPort ? base.port : null,
      path: AppRoutes.iskry,
    );
    return uri.toString();
  }

  /// _showMessage shows a short snackbar message.
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// _selectProduct updates the selected transfer card and clamps quantity.
  void _selectProduct(IskryTransferProductModel product) {
    setState(() {
      _selectedProductId = product.id;
      _quantity = _clampQuantity(product, _quantity);
    });
  }

  /// _changeQuantity updates ordered seat count.
  void _changeQuantity(int nextQuantity) {
    final product = _selectedProduct;
    if (product == null) return;
    setState(() => _quantity = _clampQuantity(product, nextQuantity));
  }

  /// build renders the public landing or the embedded payment status step.
  @override
  Widget build(BuildContext context) {
    if (_createdOrder != null) {
      return PurchaseStatusPage(
        detail: _createdOrder!,
        onClose: () {
          if (!mounted) return;
          setState(() => _createdOrder = null);
        },
      );
    }

    final authState = ref.watch(
      authControllerProvider.select((controller) => controller.state),
    );
    final selectedProduct = _selectedProduct;
    final canPay =
        _isAuthenticated &&
        !_submitting &&
        selectedProduct != null &&
        _maxSelectableSeats > 0 &&
        (_normalizedTelegram ?? '').isNotEmpty;

    return AppScaffold(
      backgroundColor: AppColors.backgroundDeep,
      bodyBackground: const _IskryPageBackground(),
      appBar: AppBar(
        title: const Text('ISKRY'),
        actions: [
          TextButton(
            onPressed:
                authState.status == AuthStatus.loading
                    ? null
                    : (_isAuthenticated
                        ? () => context.go(AppRoutes.feed)
                        : _openAuth),
            child: Text(_isAuthenticated ? 'SPACE App' : 'Войти'),
          ),
        ],
      ),
      bottomSheet: StickyActionBar(
        primaryAction: PrimaryButton(
          label: _isAuthenticated ? 'Оплатить' : 'Войти через Telegram',
          onPressed:
              _submitting
                  ? null
                  : (_isAuthenticated ? (canPay ? _submit : null) : _openAuth),
          loading: _submitting,
          expand: true,
        ),
        secondaryAction: SecondaryButton(
          label:
              selectedProduct == null
                  ? 'Выберите трансфер'
                  : 'Итого: ${formatMoney(_totalCents)}',
          onPressed: null,
          outline: true,
          expand: true,
        ),
      ),
      child: _buildBody(context, authState, canPay),
    );
  }

  /// _buildBody builds the public landing body.
  Widget _buildBody(BuildContext context, AuthState authState, bool canPay) {
    if (_loading) {
      return const Center(
        child: LoadingState(
          title: 'Загрузка ISKRY',
          subtitle: 'Получаем доступные трансферы',
        ),
      );
    }
    if ((_error ?? '').trim().isNotEmpty) {
      return Center(child: ErrorState(message: _error!, onRetry: _loadLanding));
    }

    final landing = _landing;
    if (landing == null) {
      return const Center(
        child: EmptyState(
          title: 'ISKRY недоступен',
          subtitle: 'Не удалось получить данные по трансферам.',
        ),
      );
    }

    final selectedProduct = _selectedProduct;
    final products = landing.products;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
      children: [
        ScreenHero(
          title: 'ISKRY',
          subtitle: 'Трансфер на событие ISKRY',
          summary: [
            AppBadge(
              label:
                  landing.startsAt == null
                      ? 'Space transfer'
                      : formatDateTime(landing.startsAt),
              variant: AppBadgeVariant.ghost,
            ),
            const AppBadge(
              label: '1 QR на заказ',
              variant: AppBadgeVariant.info,
            ),
            AppBadge(
              label: _isAuthenticated ? 'Telegram подключен' : 'Нужен вход',
              variant:
                  _isAuthenticated
                      ? AppBadgeVariant.accent
                      : AppBadgeVariant.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Как это работает',
          subtitle: 'Выберите рейс, количество мест и контакт Telegram',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('После оплаты QR-код придёт в Telegram.'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Если указываете другой username, этот Telegram должен хотя бы один раз войти в SPACE App.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!_isAuthenticated && authState.status != AuthStatus.loading)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: InlineStatusBanner(
              title: 'Нужен вход через Telegram',
              message:
                  'Авторизуйтесь заранее, чтобы после оплаты QR ушёл в нужный Telegram.',
              tone: InlineStatusBannerTone.info,
              actionLabel: 'Войти',
              onAction: _openAuth,
            ),
          ),
        const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: InlineStatusBanner(
              title: 'Оплата по номеру телефона',
              message:
                  'После создания заказа мы покажем реквизиты для перевода на +79841478036.',
              tone: InlineStatusBannerTone.info,
            ),
          ),
        SectionCard(
          title: 'Доступные трансферы',
          subtitle:
              products.isEmpty
                  ? 'Сейчас нет активных рейсов'
                  : 'Доступны только активные трансферы ISKRY',
          child:
              products.isEmpty
                  ? const EmptyState(
                    title: 'Рейсов пока нет',
                    subtitle:
                        'Когда администратор добавит трансфер, он появится здесь.',
                  )
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 760;
                      final cardWidth =
                          compact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - AppSpacing.sm) / 2;
                      return Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final product in products)
                            SizedBox(
                              width: cardWidth,
                              child: _IskryTransferCard(
                                product: product,
                                selected: product.id == selectedProduct?.id,
                                onTap:
                                    product.availableSeats > 0
                                        ? () => _selectProduct(product)
                                        : null,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Количество мест',
          subtitle:
              selectedProduct == null
                  ? 'Сначала выберите рейс'
                  : 'Можно купить от 1 до $_maxSelectableSeats мест',
          child: _QuantitySelector(
            quantity: _quantity,
            enabled: selectedProduct != null && _maxSelectableSeats > 0,
            maxQuantity: _maxSelectableSeats,
            onChanged: _changeQuantity,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Контакт для QR',
          subtitle:
              'Telegram обязателен. Имя и телефон можно оставить пустыми.',
          child: Column(
            children: [
              InputField(
                controller: _telegramCtrl,
                label: 'Telegram username',
                hint: '@username или t.me/username',
                errorText: _telegramCtrl.text.isEmpty ? null : _telegramError,
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _nameCtrl,
                label: 'Имя',
                hint: 'Необязательно',
              ),
              const SizedBox(height: AppSpacing.xs),
              InputField(
                controller: _phoneCtrl,
                label: 'Телефон',
                hint: 'Необязательно',
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Итог',
          subtitle:
              canPay
                  ? 'Проверка пройдена, можно переходить к оплате.'
                  : 'Заполните контакт и выберите доступный трансфер.',
          child:
              selectedProduct == null
                  ? const EmptyState(
                    title: 'Трансфер не выбран',
                    subtitle: 'Выберите один из активных рейсов выше.',
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SummaryRow(label: 'Рейс', value: selectedProduct.label),
                      _SummaryRow(label: 'Мест', value: '$_quantity'),
                      _SummaryRow(
                        label: 'Цена за место',
                        value: formatMoney(selectedProduct.priceCents),
                      ),
                      _SummaryRow(
                        label: 'Итого',
                        value: formatMoney(_totalCents),
                        emphasize: true,
                      ),
                      if ((_normalizedTelegram ?? '').isNotEmpty)
                        _SummaryRow(
                          label: 'Telegram',
                          value: _normalizedTelegram!,
                        ),
                    ],
                  ),
        ),
      ],
    );
  }
}

/// _IskryPageBackground renders the dedicated ISKRY poster background.
class _IskryPageBackground extends StatelessWidget {
  /// _IskryPageBackground creates the dedicated landing backdrop.
  const _IskryPageBackground();

  static const String _assetPath = 'assets/images/iskry/iskry_background.jpg';

  /// build renders the image background with dark overlays for readable content.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              _assetPath,
              fit: BoxFit.cover,
              alignment: const Alignment(0, 0.88),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.12),
                    AppColors.backgroundDeep.withValues(alpha: 0.28),
                    AppColors.backgroundDeep.withValues(alpha: 0.62),
                    AppColors.backgroundDeep.withValues(alpha: 0.84),
                  ],
                  stops: const <double>[0, 0.28, 0.62, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.72),
                  radius: 1.1,
                  colors: <Color>[
                    Colors.transparent,
                    AppColors.backgroundDeep.withValues(alpha: 0.1),
                    AppColors.backgroundDeep.withValues(alpha: 0.44),
                  ],
                  stops: const <double>[0.18, 0.7, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// IskryPaymentResultKind distinguishes success and fail states.
enum IskryPaymentResultKind { success, fail }

/// IskryPaymentResultPage renders success/fail copy after bank redirect.
class IskryPaymentResultPage extends ConsumerStatefulWidget {
  /// IskryPaymentResultPage creates the payment result screen.
  const IskryPaymentResultPage({
    required this.kind,
    this.orderId = '',
    super.key,
  });

  final IskryPaymentResultKind kind;
  final String orderId;

  /// createState creates state.
  @override
  ConsumerState<IskryPaymentResultPage> createState() =>
      _IskryPaymentResultPageState();
}

/// _IskryPaymentResultPageState optionally checks order delivery status for success redirects.
class _IskryPaymentResultPageState
    extends ConsumerState<IskryPaymentResultPage> {
  bool _loading = false;
  String? _error;
  SbpQrStatusResponseModel? _status;

  /// initState checks the order status when success page knows the order id and session.
  @override
  void initState() {
    super.initState();
    if (widget.kind == IskryPaymentResultKind.success &&
        widget.orderId.trim().isNotEmpty) {
      unawaited(_loadStatus());
    }
  }

  /// _token returns the current auth token when available.
  String get _token =>
      ref.read(authControllerProvider).state.token?.trim() ?? '';

  /// _maybeLoadStatus retries once auth session becomes available after page init.
  void _maybeLoadStatus() {
    if (widget.kind != IskryPaymentResultKind.success) return;
    if (widget.orderId.trim().isEmpty) return;
    if (_loading || _status != null || (_error ?? '').trim().isNotEmpty) return;
    if (_token.isEmpty) return;
    unawaited(_loadStatus());
  }

  /// _loadStatus fetches paid/order delivery state for the current order.
  Future<void> _loadStatus() async {
    if (_token.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await ref
          .read(ticketingRepositoryProvider)
          .getSbpQrStatus(token: _token, orderId: widget.orderId.trim());
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// build renders success/fail copy and optional order diagnostics.
  @override
  Widget build(BuildContext context) {
    _maybeLoadStatus();
    final isSuccess = widget.kind == IskryPaymentResultKind.success;
    final detail = _status?.detail;
    final tickets = detail?.tickets ?? const <TicketModel>[];
    final deliveredTickets = tickets.where(
      (ticket) => ticket.qrDeliveredAt != null,
    );
    final deliveryErrors =
        tickets
            .map((ticket) => ticket.qrDeliveryError.trim())
            .where((error) => error.isNotEmpty)
            .toList();

    return AppScaffold(
      appBar: AppBar(title: const Text('ISKRY')),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScreenHero(
            title: isSuccess ? 'Оплата прошла успешно.' : 'Оплата не прошла.',
            subtitle:
                isSuccess
                    ? 'QR-код отправлен в Telegram, который вы указали при оформлении.'
                    : 'Попробуйте ещё раз или напишите в поддержку.',
            summary: [
              AppBadge(
                label: isSuccess ? 'Оплата' : 'Ошибка оплаты',
                variant:
                    isSuccess ? AppBadgeVariant.accent : AppBadgeVariant.danger,
              ),
              if (widget.orderId.trim().isNotEmpty)
                AppBadge(
                  label: 'Заказ ${widget.orderId.trim()}',
                  variant: AppBadgeVariant.ghost,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            title: isSuccess ? 'Что дальше' : 'Что можно сделать',
            subtitle:
                isSuccess
                    ? 'Если сообщение не пришло, проверьте статус или напишите в поддержку.'
                    : 'Вернитесь на страницу ISKRY и попробуйте оплатить снова.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSuccess
                      ? 'Если сообщение не пришло, напишите в поддержку.'
                      : 'Если списание было, но статус не обновился, свяжитесь с поддержкой и сообщите номер заказа.',
                ),
                if (_loading) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const LoadingState(
                    title: 'Проверяем заказ',
                    subtitle: 'Сверяем статус оплаты и доставку QR',
                  ),
                ],
                if ((_error ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InlineStatusBanner(
                    title: 'Не удалось проверить статус',
                    message: _error!,
                    tone: InlineStatusBannerTone.warning,
                    actionLabel: 'Повторить',
                    onAction: _loadStatus,
                  ),
                ],
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _SummaryRow(
                    label: 'Статус заказа',
                    value: detail.order.status,
                  ),
                  _SummaryRow(
                    label: 'Сумма',
                    value: formatMoney(detail.order.totalCents),
                  ),
                  _SummaryRow(
                    label: 'Мест',
                    value: '${detail.transferSeatsCount}',
                  ),
                  if (deliveredTickets.isNotEmpty)
                    _SummaryRow(
                      label: 'QR доставлен',
                      value: formatDateTime(
                        deliveredTickets.first.qrDeliveredAt,
                      ),
                    ),
                  if (deliveryErrors.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    InlineStatusBanner(
                      title: 'Доставка требует внимания',
                      message: deliveryErrors.first,
                      tone: InlineStatusBannerTone.warning,
                    ),
                  ],
                ] else if (isSuccess &&
                    widget.orderId.trim().isNotEmpty &&
                    _token.isEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const InlineStatusBanner(
                    title: 'Чтобы проверить статус',
                    message:
                        'Откройте ISKRY из того же Telegram аккаунта, который оформлял заказ.',
                    tone: InlineStatusBannerTone.info,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            onPressed: () => context.go(AppRoutes.iskry),
            label: isSuccess ? 'Вернуться на ISKRY' : 'Попробовать ещё раз',
            expand: true,
          ),
          if (isSuccess && widget.orderId.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            SecondaryButton(
              onPressed: _token.isEmpty || _loading ? null : _loadStatus,
              label: 'Проверить статус',
              outline: true,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// _IskryTransferCard renders a public transfer product card.
class _IskryTransferCard extends StatelessWidget {
  /// _IskryTransferCard creates a transfer card.
  const _IskryTransferCard({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final IskryTransferProductModel product;
  final bool selected;
  final VoidCallback? onTap;

  /// build renders the transfer card.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final soldOut = product.availableSeats <= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color:
              selected
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.35),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: AppCard(
        onTap: onTap,
        variant: selected ? AppCardVariant.panel : AppCardVariant.surface,
        borderRadius: 24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    product.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppBadge(
                  label:
                      soldOut ? 'Sold out' : '${product.availableSeats} мест',
                  variant:
                      soldOut ? AppBadgeVariant.danger : AppBadgeVariant.accent,
                ),
              ],
            ),
            if (product.description.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(product.description.trim()),
            ],
            const SizedBox(height: AppSpacing.sm),
            _ProductMetaRow(
              label: 'Цена',
              value: formatMoney(product.priceCents),
            ),
            if (product.departurePoint.trim().isNotEmpty)
              _ProductMetaRow(
                label: 'Отправление',
                value: product.departurePoint,
              ),
            if (product.departureDateTime.trim().isNotEmpty)
              _ProductMetaRow(label: 'Время', value: product.departureDateTime),
            if (product.arrivalPoint.trim().isNotEmpty)
              _ProductMetaRow(label: 'Прибытие', value: product.arrivalPoint),
            _ProductMetaRow(
              label: 'Вместимость',
              value: '${product.capacity} мест',
            ),
          ],
        ),
      ),
    );
  }
}

/// _QuantitySelector renders simple stepper controls.
class _QuantitySelector extends StatelessWidget {
  /// _QuantitySelector creates the quantity selector.
  const _QuantitySelector({
    required this.quantity,
    required this.enabled,
    required this.maxQuantity,
    required this.onChanged,
  });

  final int quantity;
  final bool enabled;
  final int maxQuantity;
  final ValueChanged<int> onChanged;

  /// build renders the stepper control.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _StepperButton(
          icon: Icons.remove_rounded,
          enabled: enabled && quantity > 1,
          onPressed: () => onChanged(quantity - 1),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppCard(
            variant: AppCardVariant.plain,
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Text(
                  '$quantity',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? 'Максимум: $maxQuantity' : 'Недоступно',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _StepperButton(
          icon: Icons.add_rounded,
          enabled: enabled && quantity < maxQuantity,
          onPressed: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

/// _StepperButton renders a compact quantity action.
class _StepperButton extends StatelessWidget {
  /// _StepperButton creates a stepper button.
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  /// build renders the stepper action.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: FilledButton.tonal(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          fixedSize: const Size(56, 56),
          minimumSize: const Size(56, 56),
          maximumSize: const Size(56, 56),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Center(child: Icon(icon)),
      ),
    );
  }
}

/// _ProductMetaRow renders compact product metadata.
class _ProductMetaRow extends StatelessWidget {
  /// _ProductMetaRow creates a compact metadata row.
  const _ProductMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  /// build renders one product metadata line.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// _SummaryRow renders one order summary line.
class _SummaryRow extends StatelessWidget {
  /// _SummaryRow creates a compact summary row.
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  /// build renders one summary line.
  @override
  Widget build(BuildContext context) {
    final textStyle =
        emphasize
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: textStyle),
          ),
        ],
      ),
    );
  }
}
