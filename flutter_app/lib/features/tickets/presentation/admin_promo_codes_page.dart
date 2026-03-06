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
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import 'ticketing_ui_utils.dart';

/// AdminPromoCodesPage represents admin promo codes page.

class AdminPromoCodesPage extends ConsumerStatefulWidget {
  /// AdminPromoCodesPage handles admin promo codes page.
  const AdminPromoCodesPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  /// createState creates state.

  @override
  ConsumerState<AdminPromoCodesPage> createState() =>
      _AdminPromoCodesPageState();
}

/// _AdminPromoCodesPageState represents admin promo codes page state.

class _AdminPromoCodesPageState extends ConsumerState<AdminPromoCodesPage> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _usageLimitCtrl = TextEditingController();
  final TextEditingController _eventIdCtrl = TextEditingController();

  String _discountType = 'PERCENT';
  DateTime? _activeFrom;
  DateTime? _activeTo;
  bool _activeOnly = false;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<PromoCodeViewModel> _items = <PromoCodeViewModel>[];

  bool get _isPercentDiscount => _discountType == 'PERCENT';

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    _valueCtrl.text = '10';
    unawaited(_load());
  }

  /// dispose releases resources held by this instance.

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _usageLimitCtrl.dispose();
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

  /// _createPromo creates promo.

  Future<void> _createPromo() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final code = _codeCtrl.text.trim();
    final value = int.tryParse(_valueCtrl.text.trim());
    final usageLimitRaw = _usageLimitCtrl.text.trim();
    final usageLimit =
        usageLimitRaw.isEmpty ? null : int.tryParse(usageLimitRaw.trim());
    final eventIdRaw = _eventIdCtrl.text.trim();
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
        _isPercentDiscount
            ? 'Скидка в процентах должна быть больше 0'
            : 'Скидка в фиксированном формате должна быть больше 0',
      );
      return;
    }
    if (_isPercentDiscount && value > 100) {
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
    if (_activeFrom != null &&
        _activeTo != null &&
        !_activeTo!.isAfter(_activeFrom!)) {
      _showMessage('Окончание действия должно быть позже начала');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).createAdminPromoCode(
            token: token,
            code: code,
            discountType: _discountType,
            value: value,
            usageLimit: usageLimit,
            eventId: eventId,
            activeFrom: _activeFrom?.toUtc().toIso8601String(),
            activeTo: _activeTo?.toUtc().toIso8601String(),
            isActive: true,
          );
      _showMessage('Промокод создан');
      _resetCreateFields();
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// _deletePromo deletes promo.

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
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// _resetCreateFields resets create fields.

  void _resetCreateFields() {
    _codeCtrl.clear();
    _usageLimitCtrl.clear();
    _activeFrom = null;
    _activeTo = null;
    if (_isPercentDiscount) {
      _valueCtrl.text = '10';
    }
  }

  /// _pickActiveFrom handles pick active from.

  Future<void> _pickActiveFrom() async {
    final initial = _activeFrom ?? DateTime.now();
    final picked = await _pickDateTime(initial: initial);
    if (picked == null || !mounted) return;

    setState(() {
      _activeFrom = picked;
      if (_activeTo != null && !_activeTo!.isAfter(picked)) {
        _activeTo = picked.add(const Duration(hours: 1));
      }
    });
  }

  /// _pickActiveTo handles pick active to.

  Future<void> _pickActiveTo() async {
    final initial = _activeTo ?? _activeFrom ?? DateTime.now();
    final picked = await _pickDateTime(initial: initial);
    if (picked == null || !mounted) return;

    setState(() {
      _activeTo = picked;
    });
  }

  /// _pickDateTime handles pick date time.

  Future<DateTime?> _pickDateTime({
    required DateTime initial,
  }) async {
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

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(
            child: LoadingState(
              title: 'Загрузка промокодов',
              subtitle: 'Получаем актуальные скидки',
            ),
          )
        : _buildBody(context);

    if (widget.embedded) return body;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Админ-промокоды'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      title: 'Промокоды',
      subtitle: 'Управление скидками и лимитами',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74),
      child: body,
    );
  }

  /// _buildBody builds body.

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if ((_error ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ErrorState(
              message: _error!,
              onRetry: _load,
            ),
          ),
        SectionCard(
          title: 'Создать промокод',
          subtitle: 'Укажите скидку, количество срабатываний и период действия',
          child: Column(
            children: [
              InputField(
                controller: _eventIdCtrl,
                keyboardType: TextInputType.number,
                label: 'ID события (необязательно)',
                hint: 'Пусто = промокод для всех событий',
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: InputField(
                      controller: _codeCtrl,
                      label: 'Код промокода',
                      hint: 'Например SPRING25',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // Keep `value` for compatibility with older Flutter SDKs used in CI/Docker.
                      // ignore: deprecated_member_use
                      value: _discountType,
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
                      onChanged: (value) {
                        setState(() {
                          _discountType = value ?? 'PERCENT';
                          if (_isPercentDiscount &&
                              _valueCtrl.text.trim().isEmpty) {
                            _valueCtrl.text = '10';
                          }
                        });
                      },
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
                      controller: _valueCtrl,
                      keyboardType: TextInputType.number,
                      label: _isPercentDiscount
                          ? 'Скидка (%)'
                          : 'Скидка (копейки)',
                      hint: _isPercentDiscount
                          ? 'от 1 до 100'
                          : 'например 1500 = 15 RUB',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: InputField(
                      controller: _usageLimitCtrl,
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
                value: _activeFrom,
                onSelect: _pickActiveFrom,
                onClear: _activeFrom == null
                    ? null
                    : () => setState(() => _activeFrom = null),
              ),
              const SizedBox(height: AppSpacing.xs),
              _DateSelectorField(
                label: 'Окончание действия',
                value: _activeTo,
                onSelect: _pickActiveTo,
                onClear: _activeTo == null
                    ? null
                    : () => setState(() => _activeTo = null),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      onPressed: _busy ? null : _createPromo,
                      label: _busy ? 'Подождите…' : 'Создать промокод',
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _activeOnly,
                          onChanged: (value) => setState(
                            () => _activeOnly = value ?? false,
                          ),
                        ),
                        const Expanded(
                          child: Text('Показывать только активные'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SecondaryButton(
                onPressed: _load,
                label: 'Обновить список',
                outline: true,
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          title: 'Промокоды (${_items.length})',
          child: _items.isEmpty
              ? const EmptyState(
                  title: 'Промокодов нет',
                  subtitle: 'Создайте первый промокод или снимите фильтры.',
                )
              : Column(
                  children: [
                    for (final item in _items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: AppCard(
                          variant: AppCardVariant.plain,
                          child: ListTile(
                            title:
                                Text('${item.code} · ${_formatDiscount(item)}'),
                            subtitle: Text(
                              'Срабатываний: ${item.usedCount}/${item.usageLimit ?? '∞'}\n'
                              'Период: ${_formatDateRange(item.activeFrom, item.activeTo)}\n'
                              'Событие: ${item.eventId ?? 'ALL'} · Активен: ${item.isActive ? 'да' : 'нет'}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              onPressed:
                                  _busy ? null : () => _deletePromo(item.id),
                              icon: const Icon(Icons.delete_outline),
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

  /// _formatDiscount formats discount.

  String _formatDiscount(PromoCodeViewModel item) {
    if (item.discountType == 'FIXED') {
      return formatMoney(item.value);
    }
    return '${item.value}%';
  }

  /// _formatDateRange formats date range.

  String _formatDateRange(DateTime? from, DateTime? to) {
    final fromText = from == null ? 'без даты начала' : formatDateTime(from);
    final toText = to == null ? 'без даты окончания' : formatDateTime(to);
    return '$fromText — $toText';
  }

  /// _showMessage handles show message.

  void _showMessage(String text) {
    if (!mounted) return;
    AppToast.show(context, message: text);
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
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
