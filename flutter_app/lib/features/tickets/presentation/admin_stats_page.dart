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
                    'Оставьте поле пустым, чтобы получить общую статистику.',
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
                  title: 'Общая статистика',
                  subtitle: 'Сводные показатели по всем событиям.',
                  child: _statsCard(stats.global),
                ),
                const SizedBox(height: AppSpacing.sm),
                SectionCard(
                  title: 'Статистика по событиям',
                  subtitle: 'Детальный разрез по каждому событию.',
                  child: stats.events.isEmpty
                      ? const EmptyState(
                          title: 'Нет данных по событиям',
                          subtitle:
                              'Попробуйте другой фильтр или загрузите статистику без event ID.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < stats.events.length; i++) ...[
                              _statsCard(stats.events[i]),
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

  /// _statsCard handles stats card.

  Widget _statsCard(AdminStatsBreakdownModel item) {
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
            item.eventId == null
                ? 'Общий итог'
                : 'Событие ${item.eventId}: ${item.eventTitle}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text('Куплено: ${formatMoney(item.purchasedAmountCents)}'),
          Text('Куплено билетов: ${item.purchasedTicketsCount}'),
          Text('Погашено: ${formatMoney(item.redeemedAmountCents)}'),
          Text('Проверено билетов: ${item.checkedInTickets}'),
          Text('Проверено людей: ${item.checkedInPeople}'),
          const SizedBox(height: 6),
          Text('Типы билетов: ${item.ticketTypeCounts}'),
          Text('Направления трансфера: ${item.transferDirectionCounts}'),
        ],
      ),
    );
  }
}
