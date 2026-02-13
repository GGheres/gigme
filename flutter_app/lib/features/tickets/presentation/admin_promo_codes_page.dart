import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-промокоды'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if ((_error ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _eventIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'ID события (необязательный фильтр)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        decoration: const InputDecoration(labelText: 'Код'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _discountType,
                        items: const [
                          DropdownMenuItem(
                              value: 'PERCENT', child: Text('PERCENT')),
                          DropdownMenuItem(
                              value: 'FIXED', child: Text('FIXED')),
                        ],
                        onChanged: (value) =>
                            setState(() => _discountType = value ?? 'PERCENT'),
                        decoration:
                            const InputDecoration(labelText: 'Тип скидки'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _valueCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Значение'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _usageLimitCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Лимит использований'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _activeFromCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Активен с (ISO-8601)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _activeToCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Активен до (ISO-8601)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _createPromo,
                        child: Text(_busy ? 'Подождите…' : 'Создать промокод'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Checkbox(
                            value: _activeOnly,
                            onChanged: (value) =>
                                setState(() => _activeOnly = value ?? false),
                          ),
                          const Expanded(child: Text('Только активные')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _load,
                  child: const Text('Обновить список'),
                ),
                const SizedBox(height: 14),
                Text('Промокоды (${_items.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._items.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(
                          '${item.code} · ${item.discountType} ${item.value}'),
                      subtitle: Text(
                        'Использовано ${item.usedCount}/${item.usageLimit ?? '∞'} · Событие ${item.eventId ?? 'ALL'} · Активен: ${item.isActive}',
                      ),
                      trailing: IconButton(
                        onPressed: _busy ? null : () => _deletePromo(item.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
