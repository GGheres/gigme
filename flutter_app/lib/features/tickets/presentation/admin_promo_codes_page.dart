import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/admin_form_section.dart';
import '../../../ui/components/admin_list_item.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';

class AdminPromoCodesPage extends ConsumerStatefulWidget {
  const AdminPromoCodesPage({super.key});

  @override
  ConsumerState<AdminPromoCodesPage> createState() =>
      _AdminPromoCodesPageState();
}

class _AdminPromoCodesPageState extends ConsumerState<AdminPromoCodesPage> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _usageLimitCtrl = TextEditingController();
  final TextEditingController _eventIdCtrl = TextEditingController();
  final TextEditingController _activeFromCtrl = TextEditingController();
  final TextEditingController _activeToCtrl = TextEditingController();

  String _discountType = 'PERCENT';
  bool _activeOnly = false;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<PromoCodeViewModel> _items = <PromoCodeViewModel>[];

  @override
  void initState() {
    super.initState();
    _valueCtrl.text = '10';
    unawaited(_load());
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _usageLimitCtrl.dispose();
    _eventIdCtrl.dispose();
    _activeFromCtrl.dispose();
    _activeToCtrl.dispose();
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
      final items =
          await ref.read(ticketingRepositoryProvider).listAdminPromoCodes(
                token: token,
                eventId: (eventId ?? 0) > 0 ? eventId : null,
                active: _activeOnly ? true : null,
              );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _createPromo() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final code = _codeCtrl.text.trim();
    final value = int.tryParse(_valueCtrl.text.trim()) ?? -1;
    if (token.isEmpty || code.isEmpty || value < 0) {
      _showMessage('Нужны код и корректное значение скидки');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).createAdminPromoCode(
            token: token,
            code: code,
            discountType: _discountType,
            value: value,
            usageLimit: int.tryParse(_usageLimitCtrl.text.trim()),
            eventId: int.tryParse(_eventIdCtrl.text.trim()),
            activeFrom: _activeFromCtrl.text.trim().isEmpty
                ? null
                : _activeFromCtrl.text.trim(),
            activeTo: _activeToCtrl.text.trim().isEmpty
                ? null
                : _activeToCtrl.text.trim(),
            isActive: true,
          );
      _showMessage('Промокод создан');
      _codeCtrl.clear();
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePromo(String promoId) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .deleteAdminPromoCode(token: token, promoId: promoId);
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _items.where((p) => p.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-промокоды'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              children: [
                ScreenHero(
                  title: 'Промокоды',
                  subtitle:
                      'Создавайте скидочные коды и управляйте их активностью',
                  leadingIcon: Icons.local_offer_outlined,
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  metrics: [
                    heroMetric('Всего', '${_items.length}',
                        icon: Icons.confirmation_number_outlined),
                    heroMetric('Активных', '$activeCount',
                        icon: Icons.bolt_outlined,
                        accent: AppColors.success),
                  ],
                ),
                if ((_error ?? '').trim().isNotEmpty) ...[
                  InlineStatusBanner(
                    title: 'Ошибка',
                    message: _error!,
                    onRetry: _load,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AdminFormSection(
                  title: 'Новый промокод',
                  description:
                      'Код, тип скидки и её значение — обязательные поля.',
                  leadingIcon: Icons.add_circle_outline_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Код',
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _discountType,
                            items: const [
                              DropdownMenuItem(
                                  value: 'PERCENT', child: Text('Процент')),
                              DropdownMenuItem(
                                  value: 'FIXED', child: Text('Сумма')),
                            ],
                            onChanged: (value) => setState(
                                () => _discountType = value ?? 'PERCENT'),
                            decoration: const InputDecoration(
                              labelText: 'Тип скидки',
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _valueCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Значение',
                              prefixIcon: Icon(Icons.percent_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: TextField(
                            controller: _usageLimitCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Лимит использований',
                              prefixIcon: Icon(Icons.repeat_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _activeFromCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Активен с (ISO-8601)',
                        prefixIcon: Icon(Icons.schedule_rounded),
                      ),
                    ),
                    TextField(
                      controller: _activeToCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Активен до (ISO-8601)',
                        prefixIcon: Icon(Icons.event_busy_rounded),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _createPromo,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.add_rounded),
                        label: Text(_busy ? 'Создаём…' : 'Создать промокод'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AdminFormSection(
                  title: 'Фильтр списка',
                  leadingIcon: Icons.filter_alt_outlined,
                  children: [
                    TextField(
                      controller: _eventIdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ID события (необязательно)',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    SwitchListTile.adaptive(
                      value: _activeOnly,
                      onChanged: (value) =>
                          setState(() => _activeOnly = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Только активные'),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Обновить список'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Промокоды · ${_items.length}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_items.isEmpty)
                  const EmptyState(
                    title: 'Пока нет промокодов',
                    subtitle:
                        'Заполните форму выше, чтобы создать первый промокод.',
                    icon: Icons.local_offer_outlined,
                  )
                else
                  ..._items.map(_buildItem),
              ],
            ),
    );
  }

  Widget _buildItem(PromoCodeViewModel item) {
    final statusLabel = item.isActive ? 'ACTIVE' : 'INACTIVE';
    final statusColor =
        item.isActive ? AppColors.success : AppColors.textSecondary;
    final discountLabel = item.discountType == 'PERCENT'
        ? '${item.value}%'
        : '${item.value}';

    return AdminListItem(
      title: '${item.code} · $discountLabel',
      subtitleLines: [
        'Тип: ${item.discountType}',
        'Использовано ${item.usedCount}/${item.usageLimit ?? '∞'}',
        'Событие: ${item.eventId ?? 'все'}',
      ],
      status: AdminListItemStatus(
        label: statusLabel,
        foreground: statusColor,
        tint: statusColor.withValues(alpha: 0.12),
      ),
      actions: [
        IconButton(
          tooltip: 'Удалить',
          onPressed: _busy ? null : () => _deletePromo(item.id),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
