import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/notifications/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_toast.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _loggingOut = false;
  bool _localRemindersEnabled = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
      ),
      title: 'Настройки',
      subtitle: 'Управление уведомлениями и поведением приложения',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Уведомления',
            subtitle: 'Напоминания о незавершенных действиях',
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _localRemindersEnabled,
                    onChanged: _saving ? null : _setLocalRemindersEnabled,
                    title: const Text('Локальные напоминания'),
                    subtitle: Text(
                      _localRemindersEnabled
                          ? 'Приложение напомнит завершить создание события или покупку билета.'
                          : 'Локальные напоминания отключены.',
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Аккаунт',
            subtitle: 'Управление сессией входа',
            child: AppButton(
              label: 'Выйти из аккаунта',
              icon: const Icon(Icons.logout_rounded),
              variant: AppButtonVariant.danger,
              loading: _loggingOut,
              expand: true,
              onPressed: _loggingOut ? null : _confirmAndLogout,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final enabled = await ref.read(localReminderServiceProvider).isEnabled();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _localRemindersEnabled = enabled;
    });
  }

  Future<void> _setLocalRemindersEnabled(bool enabled) async {
    setState(() {
      _saving = true;
      _localRemindersEnabled = enabled;
    });

    try {
      await ref.read(localReminderServiceProvider).setEnabled(enabled);
      if (!mounted) return;
      AppToast.show(
        context,
        message: enabled
            ? 'Локальные напоминания включены'
            : 'Локальные напоминания отключены',
        tone: enabled ? AppToastTone.success : AppToastTone.info,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _localRemindersEnabled = !enabled);
      AppToast.show(
        context,
        message: 'Не удалось сохранить настройку: $error',
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Выйти из аккаунта?'),
          content: const Text(
            'Текущая сессия будет завершена на этом устройстве.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Выйти'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) return;

    setState(() => _loggingOut = true);
    try {
      await ref.read(authControllerProvider).logout();
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Вы вышли из аккаунта',
        tone: AppToastTone.info,
      );
      context.go(AppRoutes.auth);
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Не удалось выполнить выход: $error',
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go(AppRoutes.profile);
  }
}
