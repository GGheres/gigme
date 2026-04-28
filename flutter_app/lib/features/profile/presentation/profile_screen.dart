import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/event_media_url_utils.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/action_group_card.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../events/application/events_controller.dart';
import '../application/profile_controller.dart';
import 'widgets/profile_summary_card.dart';

/// ProfileScreen represents profile screen.

class ProfileScreen extends ConsumerStatefulWidget {
  /// ProfileScreen handles profile screen.
  const ProfileScreen({super.key});

  /// createState creates state.

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

/// _ProfileScreenState represents profile screen state.

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loaded = false;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(profileControllerProvider);
    final events = ref.watch(eventsControllerProvider);
    final state = controller.state;
    final config = ref.watch(appConfigProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final isAdmin = state.user != null &&
        config.adminTelegramIds.contains(state.user!.telegramId);

    if (!_loaded) {
      _loaded = true;
      unawaited(ref.read(profileControllerProvider).load());
    }

    return AppScaffold(
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
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Тема',
            onPressed: () =>
                ref.read(appThemeModeProvider.notifier).cycleMode(),
            icon: Icon(
              switch (themeMode) {
                ThemeMode.system => Icons.brightness_auto_rounded,
                ThemeMode.light => Icons.light_mode_rounded,
                ThemeMode.dark => Icons.dark_mode_rounded,
              },
            ),
          ),
        ],
      ),
      child: state.loading && state.user == null
          ? const Center(
              child: LoadingState(
                title: 'Загрузка профиля',
                subtitle: 'Проверяем данные аккаунта и ваши события',
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(profileControllerProvider).load(),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ScreenHero(
                    title: 'Профиль',
                    subtitle: isAdmin
                        ? 'Аккаунт, быстрые действия и доступ к админ-инструментам'
                        : 'Аккаунт, билеты и ваши последние события',
                    summary: [
                      AppBadge(
                        label: '${state.total} событий',
                        variant: AppBadgeVariant.neutral,
                      ),
                      AppBadge(
                        label: _themeModeLabel(themeMode),
                        variant: AppBadgeVariant.ghost,
                      ),
                      if (isAdmin)
                        const AppBadge(
                          label: 'Админ-доступ',
                          variant: AppBadgeVariant.accent,
                        ),
                    ],
                    actions: [
                      PrimaryButton(
                        label: 'Мои билеты',
                        icon: const Icon(Icons.qr_code_rounded),
                        onPressed: () => context.push(AppRoutes.myTickets),
                      ),
                      SecondaryButton(
                        label: 'Настройки',
                        icon: const Icon(Icons.settings_outlined),
                        outline: true,
                        onPressed: () => context.push(AppRoutes.settings),
                      ),
                      if (kDebugMode)
                        AppButton(
                          label: 'UI Preview',
                          variant: AppButtonVariant.ghost,
                          onPressed: () => context.push(AppRoutes.uiPreview),
                        ),
                    ],
                  ),
                  if ((state.error ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    InlineStatusBanner(
                      title: 'Не удалось обновить профиль',
                      message: state.error!,
                      tone: InlineStatusBannerTone.danger,
                      actionLabel: 'Повторить',
                      onAction: () =>
                          ref.read(profileControllerProvider).load(),
                    ),
                  ],
                  if ((state.notice ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    InlineStatusBanner(
                      title: 'Обновление профиля',
                      message: state.notice!,
                      tone: InlineStatusBannerTone.info,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ProfileSummaryCard(
                    user: state.user,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ActionGroupCard(
                    title: 'Быстрые действия',
                    subtitle: 'Самые частые переходы и настройки аккаунта.',
                    actions: [
                      PrimaryButton(
                        label: 'Открыть билеты',
                        icon: const Icon(Icons.confirmation_number_outlined),
                        expand: true,
                        onPressed: () => context.push(AppRoutes.myTickets),
                      ),
                      SecondaryButton(
                        label: 'Открыть настройки',
                        icon: const Icon(Icons.tune_rounded),
                        expand: true,
                        outline: true,
                        onPressed: () => context.push(AppRoutes.settings),
                      ),
                    ],
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ActionGroupCard(
                      title: 'Админ-инструменты',
                      subtitle:
                          'Рабочие разделы вынесены отдельно, чтобы не смешивать их с пользовательским профилем.',
                      actions: [
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            AppButton(
                              label: 'Заказы',
                              size: AppButtonSize.sm,
                              variant: AppButtonVariant.secondary,
                              onPressed: () =>
                                  context.push(AppRoutes.adminOrders),
                            ),
                            AppButton(
                              label: 'Сообщения',
                              size: AppButtonSize.sm,
                              variant: AppButtonVariant.secondary,
                              onPressed: () =>
                                  context.push(AppRoutes.adminBotMessages),
                            ),
                            AppButton(
                              label: 'QR-сканер',
                              size: AppButtonSize.sm,
                              variant: AppButtonVariant.secondary,
                              onPressed: () =>
                                  context.push(AppRoutes.adminScanner),
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
                              onPressed: () =>
                                  context.push(AppRoutes.adminPromos),
                            ),
                            AppButton(
                              label: 'Статистика',
                              size: AppButtonSize.sm,
                              variant: AppButtonVariant.secondary,
                              onPressed: () =>
                                  context.push(AppRoutes.adminStats),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ActionGroupCard(
                    title: 'Мои события',
                    subtitle:
                        'Последние события, которые вы создали или ведете.',
                    actions: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppBadge(
                          label: '${state.total} всего',
                          variant: AppBadgeVariant.ghost,
                        ),
                      ),
                      if (state.events.isEmpty)
                        const AppCard(
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
                            final fallbackImageUrl = proxyThumbnail.isNotEmpty
                                ? fallbackThumbnail
                                : '';

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
                                              Icons
                                                  .image_not_supported_outlined,
                                            ),
                                          )
                                        : Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, _, __) {
                                              if (fallbackImageUrl.isNotEmpty &&
                                                  fallbackImageUrl !=
                                                      imageUrl) {
                                                return Image.network(
                                                  fallbackImageUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (context, _, __) =>
                                                          const ColoredBox(
                                                    color: Color(0xFFE8F0F4),
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return const ColoredBox(
                                                color: Color(0xFFE8F0F4),
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                title: Text(event.title),
                                subtitle: Text(
                                  '${formatDateTime(event.startsAt)} • '
                                  '${event.participantsCount} участников',
                                ),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// _themeModeLabel handles theme mode label.

  String _themeModeLabel(ThemeMode themeMode) {
    return switch (themeMode) {
      ThemeMode.system => 'Тема: система',
      ThemeMode.light => 'Тема: светлая',
      ThemeMode.dark => 'Тема: темная',
    };
  }
}
