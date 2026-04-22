import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/admin_filter_bar.dart';
import '../../../ui/components/admin_form_section.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_radii.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

class AdminStatsPage extends ConsumerStatefulWidget {
  const AdminStatsPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  ConsumerState<AdminStatsPage> createState() => _AdminStatsPageState();
}

class _AdminStatsPageState extends ConsumerState<AdminStatsPage> {
  final TextEditingController _eventIdCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  AdminStatsModel? _stats;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _eventIdCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final global = stats?.global;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        ScreenHero(
          title: 'Статистика',
          subtitle:
              'Агрегированные продажи и чек-ины. Отфильтруйте по конкретному событию.',
          leadingIcon: Icons.bar_chart_rounded,
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          metrics: [
            if (global != null) ...[
              heroMetric('Куплено', formatMoney(global.purchasedAmountCents),
                  icon: Icons.shopping_bag_outlined,
                  accent: AppColors.success),
              heroMetric('Погашено', formatMoney(global.redeemedAmountCents),
                  icon: Icons.verified_outlined, accent: AppColors.info),
              heroMetric('Билетов чек-ин', '${global.checkedInTickets}',
                  icon: Icons.confirmation_number_outlined),
            ],
          ],
        ),
        AdminFilterBar(
          fields: [
            TextField(
              controller: _eventIdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ID события (необязательно)',
                prefixIcon: Icon(Icons.event_outlined),
              ),
              onSubmitted: (_) => _load(),
            ),
          ],
          actions: [
            FilledButton.tonalIcon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Загрузить'),
            ),
          ],
        ),
        if ((_error ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          InlineStatusBanner(
            title: 'Не удалось загрузить статистику',
            message: _error!,
            onRetry: _load,
          ),
        ],
        if (_loading) ...[
          const SizedBox(height: AppSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ] else if (stats != null) ...[
          const SizedBox(height: AppSpacing.md),
          _buildBreakdownCard(stats.global, isGlobal: true),
          const SizedBox(height: AppSpacing.md),
          Text(
            'По событиям · ${stats.events.length}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (stats.events.isEmpty)
            const EmptyState(
              title: 'Нет данных по событиям',
              subtitle: 'По выбранным фильтрам ещё нет агрегатов.',
              icon: Icons.event_busy_outlined,
            )
          else
            ...stats.events.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
                child: _buildBreakdownCard(e),
              ),
            ),
        ],
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-статистика'),
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

  Widget _buildBreakdownCard(AdminStatsBreakdownModel item,
      {bool isGlobal = false}) {
    final title = isGlobal
        ? 'Общий итог'
        : (item.eventTitle.isEmpty
            ? 'Событие #${item.eventId}'
            : item.eventTitle);
    final description = isGlobal
        ? null
        : 'ID ${item.eventId ?? '—'}';

    return AdminFormSection(
      title: title,
      description: description,
      leadingIcon: isGlobal ? Icons.public_rounded : Icons.event_outlined,
      children: [
        _metricsRow([
          _MetricTile(
            label: 'Куплено',
            value: formatMoney(item.purchasedAmountCents),
            icon: Icons.shopping_bag_outlined,
            accent: AppColors.success,
          ),
          _MetricTile(
            label: 'Погашено',
            value: formatMoney(item.redeemedAmountCents),
            icon: Icons.verified_outlined,
            accent: AppColors.info,
          ),
        ]),
        _metricsRow([
          _MetricTile(
            label: 'Билетов чек-ин',
            value: '${item.checkedInTickets}',
            icon: Icons.confirmation_number_outlined,
          ),
          _MetricTile(
            label: 'Людей чек-ин',
            value: '${item.checkedInPeople}',
            icon: Icons.groups_outlined,
          ),
        ]),
        if (item.ticketTypeCounts.isNotEmpty)
          _buildCountsGroup(
            'Типы билетов',
            item.ticketTypeCounts,
            icon: Icons.local_activity_outlined,
          ),
        if (item.transferDirectionCounts.isNotEmpty)
          _buildCountsGroup(
            'Направления трансфера',
            item.transferDirectionCounts,
            icon: Icons.directions_bus_outlined,
          ),
      ],
    );
  }

  Widget _metricsRow(List<_MetricTile> tiles) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  Widget _buildCountsGroup(String title, Map<String, int> counts,
      {required IconData icon}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final entry in counts.entries)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color:
                        theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '${entry.key} · ${entry.value}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = accent ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.30 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
