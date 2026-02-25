import 'package:flutter/material.dart';

import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';

/// UiPreviewScreen represents ui preview screen.

class UiPreviewScreen extends StatelessWidget {
  /// UiPreviewScreen handles ui preview screen.
  const UiPreviewScreen({super.key});

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'UI Preview',
      subtitle: 'Компоненты и состояния дизайн-системы',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      scrollable: true,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Buttons',
            subtitle: 'Основные кнопки и действия',
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                PrimaryButton(label: 'Primary'),
                SecondaryButton(label: 'Secondary'),
                SecondaryButton(label: 'Outline', outline: true),
                AppIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Настройки',
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Input',
            subtitle: 'Поля ввода с подсказками и ошибками',
            child: Column(
              children: <Widget>[
                InputField(
                  label: 'Название',
                  hint: 'Введите текст',
                  helper: 'Короткое понятное название',
                ),
                SizedBox(height: AppSpacing.sm),
                InputField(
                  label: 'Email',
                  initialValue: 'name@example.com',
                  errorText: 'Неверный формат email',
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Badges',
            subtitle: 'Состояния и маркеры',
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                AppBadge(label: 'Нейтральный'),
                AppBadge(label: 'Акцент', variant: AppBadgeVariant.accent),
                AppBadge(label: 'Успех', variant: AppBadgeVariant.success),
                AppBadge(label: 'Ошибка', variant: AppBadgeVariant.danger),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'States',
            subtitle: 'Loading, Empty, Error',
            child: Column(
              children: <Widget>[
                LoadingState(title: 'Загрузка данных'),
                SizedBox(height: AppSpacing.sm),
                EmptyState(
                  title: 'Пока пусто',
                  subtitle: 'Здесь появятся элементы после обновления',
                  actionLabel: 'Обновить',
                ),
                SizedBox(height: AppSpacing.sm),
                ErrorState(message: 'Не удалось получить данные'),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
