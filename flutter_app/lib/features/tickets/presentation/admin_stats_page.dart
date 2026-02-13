import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              TextField(
                controller: _eventIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ID события (необязательно)'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('Загрузить статистику'),
              ),
              if ((_error ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (stats != null) ...[
                const SizedBox(height: 12),
                Text('Общая статистика',
                    style: Theme.of(context).textTheme.titleMedium),
                _statsCard(stats.global),
                const SizedBox(height: 10),
                Text('Статистика по событиям',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (stats.events.isEmpty)
                  const Text('Нет данных по событиям')
                else
                  ...stats.events.map(_statsCard),
              ],
            ],
          );
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-статистика'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: body,
    );
  }

  Widget _statsCard(AdminStatsBreakdownModel item) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.eventId == null
                ? 'Общий итог'
                : 'Событие ${item.eventId}: ${item.eventTitle}'),
            const SizedBox(height: 6),
            Text('Куплено: ${formatMoney(item.purchasedAmountCents)}'),
            Text('Погашено: ${formatMoney(item.redeemedAmountCents)}'),
            Text('Проверено билетов: ${item.checkedInTickets}'),
            Text('Проверено людей: ${item.checkedInPeople}'),
            const SizedBox(height: 6),
            Text('Типы билетов: ${item.ticketTypeCounts}'),
            Text('Направления трансфера: ${item.transferDirectionCounts}'),
          ],
        ),
      ),
    );
  }
}
