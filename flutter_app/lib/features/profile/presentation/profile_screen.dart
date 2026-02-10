import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../application/profile_controller.dart';
import 'widgets/profile_summary_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(profileControllerProvider);
    final state = controller.state;
    final config = ref.watch(appConfigProvider);
    final isAdmin = state.user != null &&
        config.adminTelegramIds.contains(state.user!.telegramId);

    if (!_loaded) {
      _loaded = true;
      unawaited(ref.read(profileControllerProvider).load());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: () => context.push(AppRoutes.admin),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Admin panel',
            ),
          IconButton(
            onPressed: () => ref.read(profileControllerProvider).load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: state.loading && state.user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(profileControllerProvider).load(),
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if ((state.error ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        state.error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if ((state.notice ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(state.notice!),
                    ),
                  ProfileSummaryCard(
                    user: state.user,
                    loading: state.loading,
                    onTopup: () async {
                      final amount = await _askTopupAmount(context);
                      if (amount == null) return;
                      await ref
                          .read(profileControllerProvider)
                          .topupTokens(amount);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('My events',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Text('${state.total} total'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (state.events.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No events created yet'),
                      ),
                    )
                  else
                    ...state.events.map(
                      (event) => Card(
                        child: ListTile(
                          onTap: () => context.push(AppRoutes.event(event.id)),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: event.thumbnailUrl.trim().isEmpty
                                  ? const ColoredBox(
                                      color: Color(0xFFE8F0F4),
                                      child: Icon(
                                          Icons.image_not_supported_outlined),
                                    )
                                  : Image.network(
                                      event.thumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, _, __) =>
                                          const ColoredBox(
                                        color: Color(0xFFE8F0F4),
                                        child:
                                            Icon(Icons.broken_image_outlined),
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(event.title),
                          subtitle: Text(
                              '${formatDateTime(event.startsAt)} • ${event.participantsCount} going'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<int?> _askTopupAmount(BuildContext context) async {
    final ctrl = TextEditingController(text: '100');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Topup GigTokens'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (1..1,000,000)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(ctrl.text.trim());
              if (value == null || value < 1 || value > 1000000) return;
              Navigator.pop(context, value);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }
}
