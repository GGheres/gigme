import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminStatsPage represents admin stats page.

class AdminStatsPage extends ConsumerStatefulWidget {
  /// AdminStatsPage handles admin stats page.
  const AdminStatsPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  /// createState creates state.

  @override
  ConsumerState<AdminStatsPage> createState() => _AdminStatsPageState();
}

/// _AdminStatsPageState represents admin stats page state.

class _AdminStatsPageState extends ConsumerState<AdminStatsPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  AdminStatsModel? _stats;

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
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Требуется авторизация';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final eventId = int.tryParse(_eventIdCtrl.text.trim());
      final stats = await ref.read(ticketingRepositoryProvider).getAdminStats(
            token: token,
            eventId: (eventId ?? 0) > 0 ? eventId : null,
          );
      if (!mounted) return;
      setState(() {
        _stats = stats;
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

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final body = _loading
        ? const Center(
            child: LoadingState(
              title: 'Загрузка статистики',
              subtitle: 'Получаем агрегированные данные по заказам и событиям',
            ),
          )
        : ListView(
            padding: EdgeInsets.zero,
            children: [
              ScreenHero(
                title: 'Статистика',
                subtitle:
                    'Сводка по выручке, погашениям и посещаемости по событиям.',
                summary: [
                  AppBadge(
                    label: stats == null
                        ? 'Данные не загружены'
                        : '${stats.events.length} событий в отчете',
                    variant: AppBadgeVariant.neutral,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SectionCard(
                title: 'Фильтр отчета',
                subtitle:
                    'Оставьте поле пустым, чтобы показать события в одном отчете.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputField(
                      controller: _eventIdCtrl,
                      keyboardType: TextInputType.number,
                      label: 'ID события (необязательно)',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    PrimaryButton(
                      onPressed: _load,
                      label: 'Загрузить статистику',
                      expand: true,
                    ),
                  ],
                ),
              ),
              if ((_error ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                InlineStatusBanner(
                  title: 'Не удалось загрузить статистику',
                  message: _error!,
                  tone: InlineStatusBannerTone.danger,
                  actionLabel: 'Повторить',
                  onAction: _load,
                ),
              ],
              if (stats != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SectionCard(
                  title: 'Статистика по событиям',
                  subtitle: 'Билеты и трансферы разделены на отдельные формы.',
                  child: stats.events.isEmpty
                      ? const EmptyState(
                          title: 'Нет данных по событиям',
                          subtitle:
                              'Попробуйте другой фильтр или загрузите статистику без event ID.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < stats.events.length; i++) ...[
                              _eventStatsCard(stats.events[i]),
                              if (i != stats.events.length - 1)
                                const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        ),
                ),
              ],
            ],
          );
    if (widget.embedded) return body;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Админ-статистика'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      child: body,
    );
  }

  /// _eventStatsCard renders one event-level statistics block.

  Widget _eventStatsCard(AdminStatsBreakdownModel item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _eventTitle(item),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppBadge(
                label: 'Куплено: ${formatMoney(item.purchasedAmountCents)}',
                variant: AppBadgeVariant.info,
              ),
              AppBadge(
                label: 'Погашено: ${formatMoney(item.redeemedAmountCents)}',
                variant: AppBadgeVariant.ghost,
              ),
              AppBadge(
                label: 'Проверено QR: ${item.checkedInTickets}',
                variant: AppBadgeVariant.neutral,
              ),
              AppBadge(
                label: 'Проверено людей: ${item.checkedInPeople}',
                variant: AppBadgeVariant.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final ticketForm = _statsForm(
                title: 'Статистика по билетам',
                children: [
                  _metricRow('Куплено билетов', item.purchasedTicketsCount),
                  const SizedBox(height: AppSpacing.xs),
                  ..._countRows(
                    item.ticketTypeCounts,
                    emptyLabel: 'Нет заказанных билетов',
                    labelBuilder: _ticketTypeLabel,
                  ),
                ],
              );
              final transferForm = _statsForm(
                title: 'Статистика по трансферам',
                children: [
                  _metricRow(
                    'Заказано мест',
                    item.transferDirectionCounts.values.fold<int>(
                      0,
                      (sum, value) => sum + value,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ..._countRows(
                    item.transferDirectionCounts,
                    emptyLabel: 'Нет заказанных трансферов',
                    labelBuilder: _transferDirectionLabel,
                  ),
                ],
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  children: [
                    ticketForm,
                    const SizedBox(height: AppSpacing.xs),
                    transferForm,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ticketForm),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: transferForm),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// _statsForm renders a compact statistics form.

  Widget _statsForm({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }

  /// _metricRow renders one label-value statistics row.

  Widget _metricRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }

  /// _countRows renders count-map rows with readable labels.

  List<Widget> _countRows(
    Map<String, int> values, {
    required String emptyLabel,
    required String Function(String value) labelBuilder,
  }) {
    if (values.isEmpty) {
      return [
        Text(
          emptyLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    final keys = values.keys.toList()..sort();
    return [
      for (final key in keys) _metricRow(labelBuilder(key), values[key] ?? 0),
    ];
  }

  /// _ticketTypeLabel converts a ticket type code to an admin label.

  String _ticketTypeLabel(String value) {
    switch (value.toUpperCase()) {
      case 'GROUP2':
        return 'Групповой билет на 2';
      case 'GROUP10':
        return 'Групповой билет на 10';
      case 'SINGLE':
      default:
        return 'Обычный билет';
    }
  }

  /// _transferDirectionLabel converts a transfer direction code to a label.

  String _transferDirectionLabel(String value) {
    switch (value.toUpperCase()) {
      case 'BACK':
        return 'Трансфер обратно';
      case 'ROUNDTRIP':
        return 'Трансфер туда и обратно';
      case 'THERE':
      default:
        return 'Трансфер туда';
    }
  }

  /// _eventTitle returns a readable title for an event statistics block.

  String _eventTitle(AdminStatsBreakdownModel item) {
    final title = item.eventTitle.trim();
    if (item.eventId == null) {
      return title.isEmpty ? 'Событие' : title;
    }
    if (title.isEmpty) return 'Событие ${item.eventId}';
    return 'Событие ${item.eventId}: $title';
  }
}
