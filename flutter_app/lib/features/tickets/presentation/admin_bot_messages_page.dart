import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

/// AdminBotMessagesPage represents admin bot messages page.

class AdminBotMessagesPage extends ConsumerStatefulWidget {
  /// AdminBotMessagesPage handles admin bot messages page.
  const AdminBotMessagesPage({
    super.key,
    this.embedded = false,
    this.initialChatId,
  });

  final bool embedded;
  final int? initialChatId;

  /// createState creates state.

  @override
  ConsumerState<AdminBotMessagesPage> createState() =>

      /// _AdminBotMessagesPageState handles admin bot messages page state.
      _AdminBotMessagesPageState();
}

/// _AdminBotMessagesPageState represents admin bot messages page state.

class _AdminBotMessagesPageState extends ConsumerState<AdminBotMessagesPage> {
  final TextEditingController _chatIdCtrl = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  AdminBotMessagesListModel? _messages;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    final initialChatId = widget.initialChatId;
    if (initialChatId != null && initialChatId > 0) {
      _chatIdCtrl.text = '$initialChatId';
    }
    unawaited(_load());
  }

  /// dispose releases resources held by this instance.

  @override
  void dispose() {
    _chatIdCtrl.dispose();
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

  /// _promptReply handles prompt reply.

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

  /// _openBot handles open bot.

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

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final items = _messages?.items ?? <AdminBotMessageModel>[];

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Chat ID (необязательно)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _load,
                child: const Text('Фильтр'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  _chatIdCtrl.clear();
                  unawaited(_load());
                },
                child: const Text('Сброс'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
                  ? Center(child: Text(_error!))
                  : items.isEmpty
                      ? const Center(child: Text('Сообщений нет'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isIncoming = item.isIncoming;
                            final colorScheme = Theme.of(context).colorScheme;
                            final cardColor = isIncoming
                                ? colorScheme.tertiaryContainer
                                    .withValues(alpha: 0.46)
                                : colorScheme.primaryContainer
                                    .withValues(alpha: 0.46);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Chip(
                                          label: Text(
                                            isIncoming
                                                ? 'Входящее'
                                                : 'Исходящее',
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(_formatDate(item.createdAt)),
                                      ],
                                    ),
                                    Text(
                                      item.contactLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    SelectableText(item.text),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: _sending
                                              ? null
                                              : () => _promptReply(item),
                                          icon: const Icon(Icons.reply_rounded),
                                          label: const Text('Ответить'),
                                        ),
                                        FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _openBot(item.chatId),
                                          icon: const Icon(
                                              Icons.open_in_new_rounded),
                                          label: const Text('Открыть бота'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            _chatIdCtrl.text = '${item.chatId}';
                                            unawaited(_load());
                                          },
                                          child: const Text('Показать чат'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сообщения бота'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }

  /// _formatDate formats date.

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month ${local.year} $hour:$minute';
  }

  /// _showMessage handles show message.

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
