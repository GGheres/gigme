import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// AdminPromoCodesPage represents admin promo codes page.

class AdminPromoCodesPage extends ConsumerStatefulWidget {
  /// AdminPromoCodesPage handles admin promo codes page.
  const AdminPromoCodesPage({super.key});

  /// createState creates state.

  @override
  ConsumerState<AdminPromoCodesPage> createState() =>

      /// _AdminPromoCodesPageState handles admin promo codes page state.
      _AdminPromoCodesPageState();
}

/// _AdminPromoCodesPageState represents admin promo codes page state.

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
    _activeFromCtrl.dispose();
    _activeToCtrl.dispose();
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
      if (mounted) setState(() => _busy = false);
    }
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Админ-промокоды'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      title: 'Промокоды',
      subtitle: 'Управление скидками и лимитами',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.74),
      child: _loading
          ? const Center(
              child: LoadingState(
                title: 'Загрузка промокодов',
                subtitle: 'Получаем актуальные скидки',
              ),
            )
          : ListView(
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
                  subtitle: 'Настройте тип, диапазон и лимит применений',
                  child: Column(
                    children: [
                      InputField(
                        controller: _eventIdCtrl,
                        keyboardType: TextInputType.number,
                        label: 'ID события (необязательный фильтр)',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: InputField(
                              controller: _codeCtrl,
                              label: 'Код',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _discountType,
                              items: const [
                                DropdownMenuItem(
                                  value: 'PERCENT',
                                  child: Text('PERCENT'),
                                ),
                                DropdownMenuItem(
                                  value: 'FIXED',
                                  child: Text('FIXED'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _discountType = value ?? 'PERCENT',
                              ),
                              decoration: const InputDecoration(
                                  labelText: 'Тип скидки'),
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
                              label: 'Значение',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: InputField(
                              controller: _usageLimitCtrl,
                              keyboardType: TextInputType.number,
                              label: 'Лимит использований',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      InputField(
                        controller: _activeFromCtrl,
                        label: 'Активен с (ISO-8601)',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      InputField(
                        controller: _activeToCtrl,
                        label: 'Активен до (ISO-8601)',
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
                                const Expanded(child: Text('Только активные')),
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
                          subtitle:
                              'Создайте первый промокод или снимите фильтры.',
                        )
                      : Column(
                          children: [
                            for (final item in _items)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.xs),
                                child: AppCard(
                                  variant: AppCardVariant.plain,
                                  child: ListTile(
                                    title: Text(
                                      '${item.code} · ${item.discountType} ${item.value}',
                                    ),
                                    subtitle: Text(
                                      'Использовано ${item.usedCount}/${item.usageLimit ?? '∞'} · Событие ${item.eventId ?? 'ALL'} · Активен: ${item.isActive}',
                                    ),
                                    trailing: IconButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _deletePromo(item.id),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  /// _showMessage handles show message.

  void _showMessage(String text) {
    if (!mounted) return;
    AppToast.show(context, message: text);
  }
}
