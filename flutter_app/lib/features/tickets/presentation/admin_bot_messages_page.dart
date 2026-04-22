import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/providers.dart';
import '../../../ui/components/admin_filter_bar.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/inline_status_banner.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_radii.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

class AdminBotMessagesPage extends ConsumerStatefulWidget {
  const AdminBotMessagesPage({
    super.key,
    this.embedded = false,
    this.initialChatId,
  });

  final bool embedded;
  final int? initialChatId;

  @override
  ConsumerState<AdminBotMessagesPage> createState() =>
      _AdminBotMessagesPageState();
}

class _AdminBotMessagesPageState extends ConsumerState<AdminBotMessagesPage> {
  final TextEditingController _chatIdCtrl = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  AdminBotMessagesListModel? _messages;

  @override
  void initState() {
    super.initState();
    final initialChatId = widget.initialChatId;
    if (initialChatId != null && initialChatId > 0) {
      _chatIdCtrl.text = '$initialChatId';
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _chatIdCtrl.dispose();
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
      final chatId = int.tryParse(_chatIdCtrl.text.trim());
      final response =
          await ref.read(ticketingRepositoryProvider).listAdminBotMessages(
                token: token,
                chatId: (chatId ?? 0) > 0 ? chatId : null,
              );
      if (!mounted) return;
      setState(() {
        _messages = response;
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

  Future<void> _promptReply(AdminBotMessageModel item) async {
    if (_sending) return;
    final chatId = item.chatId;
    final contact = item.contactLabel.trim();
    final title = contact.isEmpty ? 'Ответ пользователю' : 'Ответ $contact';

    final textCtrl = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textCtrl,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Введите сообщение'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, textCtrl.text.trim()),
              child: const Text('Отправить'),
            ),
          ],
        );
      },
    );
    textCtrl.dispose();

    if ((message ?? '').trim().isEmpty) return;

    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      _showMessage('Требуется авторизация');
      return;
    }

    setState(() => _sending = true);
    try {
      await ref.read(ticketingRepositoryProvider).replyAdminBotMessage(
            token: token,
            chatId: chatId,
            text: message!.trim(),
          );
      await _load();
      _showMessage('Сообщение отправлено');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openBot(int chatId) async {
    final config = ref.read(appConfigProvider);
    final link = buildBotReplyDeepLink(
      botUsername: config.botUsername,
      telegramId: chatId,
    );
    if (link.isEmpty) {
      _showMessage('BOT_USERNAME не настроен');
      return;
    }

    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('Не удалось открыть Telegram');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _messages?.items ?? <AdminBotMessageModel>[];
    final uniqueChats =
        items.map((m) => m.chatId).toSet().length;
    final incoming = items.where((m) => m.isIncoming).length;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHero(
          title: 'Сообщения бота',
          subtitle:
              'Переписка пользователей — фильтруйте по чату и отвечайте прямо из админки',
          leadingIcon: Icons.forum_outlined,
          metrics: [
            heroMetric('Сообщений', '${items.length}',
                icon: Icons.chat_bubble_outline_rounded),
            heroMetric('Чатов', '$uniqueChats',
                icon: Icons.group_outlined, accent: AppColors.info),
            heroMetric('Входящих', '$incoming',
                icon: Icons.call_received_rounded,
                accent: AppColors.success),
          ],
        ),
        AdminFilterBar(
          fields: [
            TextField(
              controller: _chatIdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chat ID (необязательно)',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              onSubmitted: (_) => _load(),
            ),
          ],
          actions: [
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Фильтр'),
            ),
            FilledButton.tonalIcon(
              onPressed: _loading
                  ? null
                  : () {
                      _chatIdCtrl.clear();
                      unawaited(_load());
                    },
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Сброс'),
            ),
          ],
        ),
        if ((_error ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: InlineStatusBanner(
              title: 'Не удалось загрузить сообщения',
              message: _error!,
              onRetry: _load,
            ),
          ),
        Expanded(child: _buildList(items)),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сообщения бота'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildList(List<AdminBotMessageModel> items) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty && (_error ?? '').isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: EmptyState(
          title: 'Сообщений нет',
          subtitle:
              'Здесь появятся входящие и исходящие сообщения Telegram-бота.',
          icon: Icons.chat_bubble_outline_rounded,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildMessageCard(items[index]),
    );
  }

  Widget _buildMessageCard(AdminBotMessageModel item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isIncoming = item.isIncoming;
    final accent = isIncoming ? AppColors.success : AppColors.primary;
    final bg = accent.withValues(alpha: isDark ? 0.14 : 0.08);
    final border = accent.withValues(alpha: isDark ? 0.35 : 0.22);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + 2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isIncoming
                          ? Icons.call_received_rounded
                          : Icons.call_made_rounded,
                      size: 12,
                      color: accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isIncoming ? 'Входящее' : 'Исходящее',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(item.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.contactLabel.isEmpty
                ? 'Чат #${item.chatId}'
                : item.contactLabel,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(item.text),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton.tonalIcon(
                onPressed: _sending ? null : () => _promptReply(item),
                icon: const Icon(Icons.reply_rounded, size: 18),
                label: const Text('Ответить'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openBot(item.chatId),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Открыть бота'),
              ),
              TextButton.icon(
                onPressed: () {
                  _chatIdCtrl.text = '${item.chatId}';
                  unawaited(_load());
                },
                icon: const Icon(Icons.filter_alt_rounded, size: 18),
                label: const Text('Показать чат'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month ${local.year} $hour:$minute';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
