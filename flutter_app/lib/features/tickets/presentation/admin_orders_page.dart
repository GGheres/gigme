import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminOrdersPage represents admin orders page.

class AdminOrdersPage extends ConsumerStatefulWidget {
  /// AdminOrdersPage handles admin orders page.
  const AdminOrdersPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  /// createState creates state.

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

/// _AdminOrdersPageState represents admin orders page state.

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  String _status = '';
  bool _loading = true;
  String? _error;
  OrdersListModel? _orders;
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

  /// _load loads data from the underlying source.

  Future<void> _load() async {
    final authState = ref.read(authControllerProvider).state;
    final token = authState.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        _loading = authState.status == AuthStatus.loading;
        _error = authState.status == AuthStatus.loading
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

  /// _handleAuthStateChange reloads orders after delayed session restore.

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
        _orders = null;
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

    final items = _orders?.items ?? <OrderSummaryModel>[];

    final body = _buildBody(context, items);
    if (widget.embedded) return body;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Админ-заказы'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      title: 'Заказы',
      subtitle: 'Мониторинг платежей и статусов',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74),
      child: body,
    );
  }

  /// _buildBody builds body.

  Widget _buildBody(BuildContext context, List<OrderSummaryModel> items) {
    return Column(
      children: [
        ScreenHero(
          title: 'Заказы',
          subtitle: 'Мониторинг платежей, фильтрация по событию и статусам.',
          summary: [
            AppBadge(
              label: '${items.length} заказов',
              variant: AppBadgeVariant.neutral,
            ),
            AppBadge(
              label: _status.trim().isEmpty ? 'Все статусы' : _status,
              variant: AppBadgeVariant.ghost,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Фильтры',
          subtitle: 'Сузьте выдачу по событию и статусу',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputField(
                      controller: _eventIdCtrl,
                      keyboardType: TextInputType.number,
                      label: 'ID события',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Статус'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Все')),
                        DropdownMenuItem(
                            value: 'PENDING', child: Text('PENDING')),
                        DropdownMenuItem(value: 'PAID', child: Text('PAID')),
                        DropdownMenuItem(
                          value: 'CONFIRMED',
                          child: Text('CONFIRMED'),
                        ),
                        DropdownMenuItem(
                            value: 'CANCELED', child: Text('CANCELED')),
                        DropdownMenuItem(
                            value: 'REDEEMED', child: Text('REDEEMED')),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? ''),
                    ),
                  ),
                ],
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
            title: 'Не удалось загрузить заказы',
            message: _error!,
            tone: InlineStatusBannerTone.danger,
            actionLabel: 'Повторить',
            onAction: _load,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _loading
              ? const Center(
                  child: LoadingState(
                    title: 'Загрузка заказов',
                    subtitle: 'Получаем последние платежи',
                  ),
                )
              : (_error != null)
                  ? const SizedBox.shrink()
                  : items.isEmpty
                      ? const Center(
                          child: EmptyState(
                            title: 'Заказов нет',
                            subtitle: 'Попробуйте изменить фильтры поиска.',
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final order = item.order;
                            final status = order.status;
                            final userTelegramId = item.user?.telegramId ?? 0;
                            final userDisplay = item.user?.displayName ??
                                'Пользователь #${order.userId}';
                            final userHandle = item.user?.usernameLabel ?? '';
                            final subtitleLines = <String>[
                              'Заказ ${order.id}',
                              userDisplay,
                            ];
                            if (userHandle.isNotEmpty &&
                                userHandle != userDisplay.trim()) {
                              subtitleLines.add(userHandle);
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: AppCard(
                                variant: AppCardVariant.plain,
                                child: ListTile(
                                  onTap: () => context.push(
                                    AppRoutes.adminOrderDetail(order.id),
                                  ),
                                  title: Text(
                                    order.eventTitle.isEmpty
                                        ? 'Событие #${order.eventId}'
                                        : order.eventTitle,
                                  ),
                                  subtitle: Text(subtitleLines.join('\n')),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (userTelegramId > 0)
                                        IconButton(
                                          tooltip: 'Диалог',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => context.push(
                                            AppRoutes.adminBotMessagesForChat(
                                              userTelegramId,
                                            ),
                                          ),
                                          icon:
                                              const Icon(Icons.forum_outlined),
                                        ),
                                      if (userTelegramId > 0)
                                        IconButton(
                                          tooltip: 'Открыть бота',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _openBotForUser(userTelegramId),
                                          icon: const Icon(
                                              Icons.open_in_new_rounded),
                                        ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Chip(
                                            label: Text(status),
                                            backgroundColor:
                                                statusColor(status, context)
                                                    .withValues(alpha: 0.12),
                                            side: BorderSide(
                                              color:
                                                  statusColor(status, context),
                                            ),
                                            labelStyle: TextStyle(
                                              color:
                                                  statusColor(status, context),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(formatMoney(order.totalCents)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  /// _openBotForUser handles open bot for user.

  Future<void> _openBotForUser(int telegramId) async {
    final config = ref.read(appConfigProvider);
    final link = buildBotReplyDeepLink(
      botUsername: config.botUsername,
      telegramId: telegramId,
    );
    if (link.isEmpty) {
      _showMessage('BOT_USERNAME не настроен');
      return;
    }

    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('Не удалось открыть Telegram');
    }
  }

  /// _showMessage handles show message.

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
