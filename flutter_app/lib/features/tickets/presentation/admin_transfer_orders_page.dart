import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/admin_panel_background.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_radii.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminTransferOrdersPage represents admin transfer orders page.

class AdminTransferOrdersPage extends ConsumerStatefulWidget {
  /// AdminTransferOrdersPage handles admin transfer orders page.
  const AdminTransferOrdersPage({super.key, this.embedded = false});

  final bool embedded;

  /// createState creates state.

  @override
  ConsumerState<AdminTransferOrdersPage> createState() =>
      _AdminTransferOrdersPageState();
}

/// _AdminTransferOrdersPageState represents admin transfer orders page state.

class _AdminTransferOrdersPageState
    extends ConsumerState<AdminTransferOrdersPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  String _status = '';
  String _direction = '';
  bool _loading = true;
  String? _error;
  AdminTransferOrdersListModel? _transfers;
  List<TransferProductModel> _transferProducts = <TransferProductModel>[];
  final Set<int> _movingItemIds = <int>{};
  String? _lastLoadedToken;
  String? _scheduledReloadToken;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// dispose releases resources held by this instance.

  @override
  void dispose() {
    _eventIdCtrl.dispose();
    super.dispose();
  }

  /// _load loads ordered transfer rows.

  Future<void> _load() async {
    final authState = ref.read(authControllerProvider).state;
    final token = authState.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        _loading = authState.status == AuthStatus.loading;
        _error =
            authState.status == AuthStatus.loading
                ? null
                : 'Требуется авторизация';
      });
      return;
    }

    _lastLoadedToken = token;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final eventId = int.tryParse(_eventIdCtrl.text.trim());
      final normalizedEventId = (eventId ?? 0) > 0 ? eventId : null;
      final repo = ref.read(ticketingRepositoryProvider);
      final results = await Future.wait<Object>([
        repo.listAdminTransferOrders(
          token: token,
          eventId: normalizedEventId,
          status: _status.trim().isEmpty ? null : _status,
          direction: _direction.trim().isEmpty ? null : _direction,
        ),
        repo.listAdminTransferProducts(
          token: token,
          eventId: normalizedEventId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _transfers = results[0] as AdminTransferOrdersListModel;
        _transferProducts = results[1] as List<TransferProductModel>;
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

  /// _handleAuthStateChange reloads transfers after delayed session restore.

  void _handleAuthStateChange(AuthState? previous, AuthState next) {
    if (!mounted) return;
    final previousToken = previous?.token?.trim() ?? '';
    final nextToken = next.token?.trim() ?? '';

    if (nextToken.isNotEmpty && nextToken != previousToken) {
      _scheduleReload(nextToken);
      return;
    }

    if (nextToken.isEmpty && next.status == AuthStatus.loading) {
      if (_loading && _error == null) {
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });
      return;
    }

    if (nextToken.isEmpty && next.status == AuthStatus.unauthenticated) {
      setState(() {
        _lastLoadedToken = null;
        _loading = false;
        _error = 'Требуется авторизация';
        _transfers = null;
        _transferProducts = <TransferProductModel>[];
      });
    }
  }

  /// _scheduleReload reloads once when a restored token becomes available.

  void _scheduleReload(String token) {
    if (_scheduledReloadToken == token) {
      return;
    }
    _scheduledReloadToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledReloadToken != token) {
        return;
      }
      _scheduledReloadToken = null;
      unawaited(_load());
    });
  }

  /// _reloadIfSessionWasRestored catches auth restore that completed before listen.

  void _reloadIfSessionWasRestored(AuthState authState) {
    final token = authState.token?.trim() ?? '';
    if (token.isEmpty || _loading || _lastLoadedToken == token) {
      return;
    }
    _scheduleReload(token);
  }

  /// _moveTransferOrder moves one transfer item to another product.

  Future<void> _moveTransferOrder(
    AdminTransferOrderModel item,
    String targetProductId,
  ) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() => _error = 'Требуется авторизация');
      return;
    }
    final normalizedTarget = targetProductId.trim();
    if (normalizedTarget.isEmpty || normalizedTarget == item.item.productId) {
      return;
    }

    setState(() => _movingItemIds.add(item.item.id));
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .moveAdminTransferOrder(
            token: token,
            itemId: item.item.id,
            targetProductId: normalizedTarget,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Трансфер перенесен')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _movingItemIds.remove(item.item.id));
      }
    }
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(
      authControllerProvider.select((controller) => controller.state),
    );
    ref.listen<AuthState>(
      authControllerProvider.select((controller) => controller.state),
      _handleAuthStateChange,
    );
    _reloadIfSessionWasRestored(authState);

    final items = _transfers?.items ?? <AdminTransferOrderModel>[];
    final body = _buildBody(context, items);
    if (widget.embedded) return body;

    return AppScaffold(
      bodyBackground: const AdminPanelBackground(),
      appBar: AppBar(
        title: const Text('Админ-трансферы'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      title: 'Трансферы',
      subtitle: 'Отдельный список заказанных мест на трансфер',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.74),
      child: body,
    );
  }

  /// _buildBody builds the transfer orders body.

  Widget _buildBody(BuildContext context, List<AdminTransferOrderModel> items) {
    final totalSeats = items.fold<int>(
      0,
      (sum, item) => sum + item.item.quantity,
    );

    return Column(
      children: [
        ScreenHero(
          title: 'Заказанные трансферы',
          subtitle: 'Контроль мест, статусов оплаты и пользователей.',
          summary: [
            AppBadge(
              label: '${items.length} заказов',
              variant: AppBadgeVariant.neutral,
            ),
            AppBadge(label: '$totalSeats мест', variant: AppBadgeVariant.info),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Фильтры',
          subtitle: 'Сузьте список по событию, статусу и продукту трансфера',
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final fields = _filterFields();
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        for (var i = 0; i < fields.length; i++) ...[
                          fields[i],
                          if (i != fields.length - 1)
                            const SizedBox(height: AppSpacing.xs),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        Expanded(child: fields[i]),
                        if (i != fields.length - 1)
                          const SizedBox(width: AppSpacing.xs),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                onPressed: _loading ? null : _load,
                label: _loading ? 'Загрузка…' : 'Применить фильтры',
                expand: true,
              ),
            ],
          ),
        ),
        if ((_error ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineStatusBanner(
            title: 'Не удалось загрузить трансферы',
            message: _error!,
            tone: InlineStatusBannerTone.danger,
            actionLabel: 'Повторить',
            onAction: _load,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child:
              _loading
                  ? const Center(
                    child: LoadingState(
                      title: 'Загрузка трансферов',
                      subtitle: 'Получаем заказанные места',
                    ),
                  )
                  : (_error != null)
                  ? const SizedBox.shrink()
                  : items.isEmpty
                  ? const Center(
                    child: EmptyState(
                      title: 'Трансферов нет',
                      subtitle: 'Пока нет заказанных трансферов.',
                    ),
                  )
                  : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _TransferOrderCard(
                        item: item,
                        moving: _movingItemIds.contains(item.item.id),
                        products: _productsForItem(item),
                        onMove:
                            (targetProductId) =>
                                _moveTransferOrder(item, targetProductId),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  /// _filterFields builds the responsive filter controls.

  List<Widget> _filterFields() {
    return [
      InputField(
        controller: _eventIdCtrl,
        keyboardType: TextInputType.number,
        label: 'ID события',
      ),
      DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _status,
        decoration: const InputDecoration(labelText: 'Статус'),
        items: const [
          DropdownMenuItem(value: '', child: Text('Все')),
          DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
          DropdownMenuItem(value: 'PAID', child: Text('PAID')),
          DropdownMenuItem(value: 'CONFIRMED', child: Text('CONFIRMED')),
          DropdownMenuItem(value: 'CANCELED', child: Text('CANCELED')),
          DropdownMenuItem(value: 'REDEEMED', child: Text('REDEEMED')),
        ],
        onChanged: (value) => setState(() => _status = value ?? ''),
      ),
      DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: _direction,
        decoration: const InputDecoration(labelText: 'Продукт трансфера'),
        items: const [
          DropdownMenuItem(value: '', child: Text('Все')),
          DropdownMenuItem(value: 'THERE', child: Text('Трансфер туда')),
          DropdownMenuItem(value: 'BACK', child: Text('Трансфер обратно')),
          DropdownMenuItem(
            value: 'ROUNDTRIP',
            child: Text('Трансфер туда и обратно'),
          ),
        ],
        onChanged: (value) => setState(() => _direction = value ?? ''),
      ),
    ];
  }

  /// _productsForItem returns transfer products available for the item's event.

  List<TransferProductModel> _productsForItem(AdminTransferOrderModel item) {
    final products =
        _transferProducts
            .where((product) => product.eventId == item.eventId)
            .toList();
    products.sort((left, right) {
      final leftRank = _directionRank(left.direction);
      final rightRank = _directionRank(right.direction);
      if (leftRank != rightRank) return leftRank.compareTo(rightRank);
      return left.label.compareTo(right.label);
    });
    return products;
  }

  /// _directionRank returns a stable sort rank for transfer directions.

  int _directionRank(String direction) {
    switch (direction.toUpperCase()) {
      case 'THERE':
        return 0;
      case 'BACK':
        return 1;
      case 'ROUNDTRIP':
        return 2;
      default:
        return 3;
    }
  }
}

/// _TransferOrderCard represents an ordered transfer card.

class _TransferOrderCard extends StatefulWidget {
  /// _TransferOrderCard handles ordered transfer card.
  const _TransferOrderCard({
    required this.item,
    required this.products,
    required this.moving,
    required this.onMove,
  });

  final AdminTransferOrderModel item;
  final List<TransferProductModel> products;
  final bool moving;
  final ValueChanged<String> onMove;

  /// createState creates state.

  @override
  State<_TransferOrderCard> createState() => _TransferOrderCardState();
}

/// _TransferOrderCardState stores the selected target product.

class _TransferOrderCardState extends State<_TransferOrderCard> {
  String? _targetProductId;

  /// initState initializes the selected target product.

  @override
  void initState() {
    super.initState();
    _targetProductId = _initialTargetProductId();
  }

  /// didUpdateWidget keeps selected product valid after list reloads.

  @override
  void didUpdateWidget(covariant _TransferOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentStillExists = widget.products.any(
      (product) => product.id == _targetProductId,
    );
    if (oldWidget.item.item.productId != widget.item.item.productId ||
        !currentStillExists) {
      _targetProductId = _initialTargetProductId();
    }
  }

  /// _initialTargetProductId returns the current product id when available.

  String? _initialTargetProductId() {
    final currentProductId = widget.item.item.productId.trim();
    if (widget.products.any((product) => product.id == currentProductId)) {
      return currentProductId;
    }
    return null;
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userDisplay =
        item.user?.displayName ?? 'Пользователь #${item.userId}';
    final createdAt = item.orderCreatedAt?.toLocal().toString() ?? '';
    final title =
        item.eventTitle.isEmpty ? 'Событие #${item.eventId}' : item.eventTitle;
    final status = item.orderStatus;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        variant: AppCardVariant.plain,
        borderRadius: AppRadii.xxl,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap:
                    () =>
                        context.push(AppRoutes.adminOrderDetail(item.orderId)),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _orderSummary(
                    context,
                    item,
                    title,
                    status,
                    userDisplay,
                    createdAt,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.35),
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.08),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: _moveControls(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// _orderSummary renders static transfer order details.

  Widget _orderSummary(
    BuildContext context,
    AdminTransferOrderModel item,
    String title,
    String status,
    String userDisplay,
    String createdAt,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.airport_shuttle_rounded),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Chip(
              label: Text(status),
              backgroundColor: statusColor(
                status,
                context,
              ).withValues(alpha: 0.12),
              side: BorderSide(color: statusColor(status, context)),
              labelStyle: TextStyle(
                color: statusColor(status, context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('Заказ ${item.orderId}'),
        Text(userDisplay),
        if (item.contactTelegram.trim().isNotEmpty) Text(item.contactTelegram),
        if (item.contactName.trim().isNotEmpty ||
            item.contactPhone.trim().isNotEmpty)
          Text(
            [
              if (item.contactName.trim().isNotEmpty) item.contactName.trim(),
              if (item.contactPhone.trim().isNotEmpty) item.contactPhone.trim(),
            ].join(' · '),
          ),
        Text(item.item.displayName),
        if (createdAt.isNotEmpty) Text(createdAt),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            AppBadge(
              label: '${item.item.quantity} мест',
              variant: AppBadgeVariant.info,
            ),
            AppBadge(
              label: formatMoney(item.item.lineTotalCents),
              variant: AppBadgeVariant.ghost,
            ),
          ],
        ),
      ],
    );
  }

  /// _moveControls renders product selector and move action.

  Widget _moveControls(BuildContext context) {
    if (widget.products.isEmpty) {
      return Text(
        'Нет доступных продуктов трансфера для этого события',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final currentProductId = widget.item.item.productId.trim();
    final selectedProductId = _targetProductId;
    final canMove =
        selectedProductId != null &&
        selectedProductId.trim().isNotEmpty &&
        selectedProductId != currentProductId &&
        !widget.moving;

    return LayoutBuilder(
      builder: (context, constraints) {
        final selector = DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _dropdownValue(),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Перенести в продукт'),
          items: [
            for (final product in widget.products)
              DropdownMenuItem(
                value: product.id,
                child: Text(
                  _productLabel(product),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged:
              widget.moving
                  ? null
                  : (value) => setState(() => _targetProductId = value),
        );
        final action = SecondaryButton(
          label: widget.moving ? 'Перенос…' : 'Перенести',
          icon: const Icon(Icons.swap_horiz_rounded),
          loading: widget.moving,
          onPressed:
              canMove ? () => widget.onMove(selectedProductId.trim()) : null,
          expand: constraints.maxWidth < 640,
        );
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [selector, const SizedBox(height: AppSpacing.xs), action],
          );
        }
        return Row(
          children: [
            Expanded(child: selector),
            const SizedBox(width: AppSpacing.xs),
            action,
          ],
        );
      },
    );
  }

  /// _dropdownValue returns a valid dropdown value for current products.

  String? _dropdownValue() {
    final value = _targetProductId?.trim();
    if (value == null || value.isEmpty) return null;
    if (widget.products.any((product) => product.id == value)) return value;
    return null;
  }

  /// _productLabel returns a compact transfer product label.

  String _productLabel(TransferProductModel product) {
    final activeSuffix = product.isActive ? '' : ' · выключен';
    return '${product.label} · ${formatMoney(product.priceCents)}$activeSuffix';
  }
}
