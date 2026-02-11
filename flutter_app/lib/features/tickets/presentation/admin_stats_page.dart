import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

class AdminStatsPage extends ConsumerStatefulWidget {
  const AdminStatsPage({super.key});

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
        _error = 'Authorization required';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin stats'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: _eventIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Event ID (optional)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: _load, child: const Text('Load stats')),
                if ((_error ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                if (stats != null) ...[
                  const SizedBox(height: 12),
                  Text('Global totals',
                      style: Theme.of(context).textTheme.titleMedium),
                  _statsCard(stats.global),
                  const SizedBox(height: 10),
                  Text('Per-event totals',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  if (stats.events.isEmpty)
                    const Text('No per-event data')
                  else
                    ...stats.events.map(_statsCard),
                ],
              ],
            ),
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
                ? 'Global'
                : 'Event ${item.eventId}: ${item.eventTitle}'),
            const SizedBox(height: 6),
            Text('Purchased amount: ${formatMoney(item.purchasedAmountCents)}'),
            Text('Redeemed amount: ${formatMoney(item.redeemedAmountCents)}'),
            const SizedBox(height: 6),
            Text('Ticket counts: ${item.ticketTypeCounts}'),
            Text('Transfer counts: ${item.transferDirectionCounts}'),
          ],
        ),
      ),
    );
  }
}
