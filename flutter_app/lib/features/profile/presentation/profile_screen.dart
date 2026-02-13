import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/event_media_url_utils.dart';
import '../../../core/widgets/premium_loading_view.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_modal.dart';
import '../../../ui/components/app_text_field.dart';
import '../../events/application/events_controller.dart';
import '../application/profile_controller.dart';
import 'widgets/profile_summary_card.dart';

// TODO(ui-migration): finish profile page shell/list tiles using AppScaffold/AppCard/AppButton tokens.
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
    final events = ref.watch(eventsControllerProvider);
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
        title: const Text('Профиль'),
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: () => context.push(AppRoutes.admin),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Админ-панель',
            ),
          IconButton(
            onPressed: () => ref.read(profileControllerProvider).load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: state.loading && state.user == null
          ? const PremiumLoadingView(
              text: 'PROFILE • LOADING • ',
              subtitle: 'Загружаем профиль',
            )
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
                  FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.myTickets),
                    icon: const Icon(Icons.qr_code_rounded),
                    label: const Text('Мои билеты'),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppButton(
                          label: 'Заказы',
                          size: AppButtonSize.sm,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.push(AppRoutes.adminOrders),
                        ),
                        AppButton(
                          label: 'QR-сканер',
                          size: AppButtonSize.sm,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.push(AppRoutes.adminScanner),
                        ),
                        AppButton(
                          label: 'Продукты',
                          size: AppButtonSize.sm,
                          variant: AppButtonVariant.secondary,
                          onPressed: () =>
                              context.push(AppRoutes.adminProducts),
                        ),
                        AppButton(
                          label: 'Промокоды',
                          size: AppButtonSize.sm,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.push(AppRoutes.adminPromos),
                        ),
                        AppButton(
                          label: 'Статистика',
                          size: AppButtonSize.sm,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.push(AppRoutes.adminStats),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Мои события',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Text('${state.total} всего'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (state.events.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Событий пока нет'),
                      ),
                    )
                  else
                    ...state.events.map(
                      (event) {
                        final accessKey = events.accessKeyFor(event.id);
                        final fallbackThumbnail = event.thumbnailUrl.trim();
                        final proxyThumbnail = buildEventMediaProxyUrl(
                          apiUrl: config.apiUrl,
                          eventId: event.id,
                          index: 0,
                          accessKey: accessKey,
                        );
                        final imageUrl = proxyThumbnail.isNotEmpty
                            ? proxyThumbnail
                            : fallbackThumbnail;
                        final fallbackImageUrl =
                            proxyThumbnail.isNotEmpty ? fallbackThumbnail : '';

                        return Card(
                          child: ListTile(
                            onTap: () =>
                                context.push(AppRoutes.event(event.id)),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: imageUrl.isEmpty
                                    ? const ColoredBox(
                                        color: Color(0xFFE8F0F4),
                                        child: Icon(
                                            Icons.image_not_supported_outlined),
                                      )
                                    : Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, _, __) {
                                          if (fallbackImageUrl.isNotEmpty &&
                                              fallbackImageUrl != imageUrl) {
                                            return Image.network(
                                              fallbackImageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, _, __) =>
                                                  const ColoredBox(
                                                color: Color(0xFFE8F0F4),
                                                child: Icon(Icons
                                                    .broken_image_outlined),
                                              ),
                                            );
                                          }
                                          return const ColoredBox(
                                            color: Color(0xFFE8F0F4),
                                            child: Icon(
                                                Icons.broken_image_outlined),
                                          );
                                        },
                                      ),
                              ),
                            ),
                            title: Text(event.title),
                            subtitle: Text(
                                '${formatDateTime(event.startsAt)} • ${event.participantsCount} участников'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Future<int?> _askTopupAmount(BuildContext context) async {
    final ctrl = TextEditingController(text: '100');
    final formKey = GlobalKey<FormState>();
    final result = await showAppDialog<int>(
      context: context,
      builder: (context) => AppModal(
        title: 'Пополнение GigTokens',
        subtitle: 'Введите сумму от 1 до 1 000 000.',
        onClose: () => Navigator.pop(context),
        body: Form(
          key: formKey,
          child: AppTextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            label: 'Сумма',
            hint: '100',
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null || parsed < 1 || parsed > 1000000) {
                return 'Введите значение от 1 до 1 000 000';
              }
              return null;
            },
          ),
        ),
        actions: [
          AppButton(
            label: 'Отмена',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.pop(context),
          ),
          AppButton(
            label: 'Применить',
            variant: AppButtonVariant.secondary,
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, int.parse(ctrl.text.trim()));
            },
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }
}
