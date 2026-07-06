import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'widgets/ticket_card.dart';

/// MyTicketsPage represents my tickets page.

class MyTicketsPage extends ConsumerStatefulWidget {
  /// MyTicketsPage handles my tickets page.
  const MyTicketsPage({super.key});

  /// createState creates state.

  @override
  ConsumerState<MyTicketsPage> createState() => _MyTicketsPageState();
}

/// _MyTicketsPageState represents my tickets page state.

class _MyTicketsPageState extends ConsumerState<MyTicketsPage>
    with WidgetsBindingObserver {
  static const Duration _refreshInterval = Duration(seconds: 15);

  String? _loadedToken;
  bool _loading = true;
  bool _requestInFlight = false;
  String? _error;
  List<TicketModel> _tickets = <TicketModel>[];
  Timer? _refreshTimer;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => unawaited(_load(showLoading: false)),
    );
  }

  /// dispose releases page resources.

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// didChangeAppLifecycleState refreshes tickets after returning to the app.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(showLoading: false));
    }
  }

  /// _load loads data from the underlying source.

  Future<void> _load({bool showLoading = true}) async {
    if (_requestInFlight) return;

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

    _requestInFlight = true;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (_error != null) {
      setState(() {
        _error = null;
      });
    }

    try {
      final response = await ref
          .read(ticketingRepositoryProvider)
          .listMyTickets(token: token);
      if (!mounted) return;
      setState(() {
        _tickets = response.items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    } finally {
      _requestInFlight = false;
    }
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).state;
    final token = authState.token?.trim() ?? '';
    if (authState.status == AuthStatus.authenticated &&
        token.isNotEmpty &&
        _loadedToken != token) {
      _loadedToken = token;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_load());
      });
    } else if (authState.status != AuthStatus.authenticated &&
        _loadedToken != null) {
      _loadedToken = null;
    }

    final visibleError =
        _error ??
        (authState.status == AuthStatus.unauthenticated && _tickets.isEmpty
            ? 'Требуется авторизация'
            : null);

    return AppScaffold(
      appBar: AppBar(leading: BackButton(onPressed: _handleBack)),
      child: Column(
        children: [
          ScreenHero(
            title: 'Мои билеты и трансферы',
            subtitle:
                'Все активные, ожидающие и использованные QR-коды в одном месте.',
            summary: [
              AppBadge(
                label: '${_tickets.length} QR',
                variant: AppBadgeVariant.neutral,
              ),
              const AppBadge(
                label: 'QR для входа и посадки',
                variant: AppBadgeVariant.ghost,
              ),
            ],
            actions: [
              SecondaryButton(
                label: 'Обновить',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
                outline: true,
              ),
            ],
          ),
          if (visibleError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InlineStatusBanner(
              title: 'Не удалось загрузить билеты',
              message: visibleError,
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
                        title: 'Загрузка билетов',
                        subtitle: 'Проверяем активные заказы',
                      ),
                    )
                    : (visibleError != null)
                    ? const SizedBox.shrink()
                    : _tickets.isEmpty
                    ? const Center(
                      child: EmptyState(
                        title: 'QR-кодов пока нет',
                        subtitle:
                            'После подтверждения заказа здесь появится QR-код',
                      ),
                    )
                    : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _tickets.length,
                      itemBuilder: (context, index) {
                        final ticket = _tickets[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: TicketCard(ticket: ticket),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  /// _handleBack handles back.

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go(AppRoutes.profile);
  }
}
