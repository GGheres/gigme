import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/event_comment.dart';
import '../../../core/models/event_detail.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/event_media_url_utils.dart';
import '../../../core/utils/share_utils.dart';
import '../../../core/widgets/premium_loading_view.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../../auth/application/auth_controller.dart';
import '../../tickets/presentation/purchase_ticket_flow.dart';
import '../application/events_controller.dart';

// TODO(ui-migration): migrate details/comments/participants blocks to AppScaffold and App* components.
class EventDetailsScreen extends ConsumerStatefulWidget {
  const EventDetailsScreen({
    required this.eventId,
    this.eventKey,
    super.key,
  });

  final int eventId;
  final String? eventKey;

  @override
  ConsumerState<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends ConsumerState<EventDetailsScreen> {
  EventDetail? _detail;
  List<EventComment> _comments = <EventComment>[];
  String _commentInput = '';

  bool _loading = true;
  bool _joining = false;
  bool _sharing = false;
  bool _sendingComment = false;
  bool _deletingEvent = false;
  final Set<int> _deletingCommentIds = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final events = ref.read(eventsControllerProvider);
      final detail = await events.loadEventDetail(
        eventId: widget.eventId,
        accessKey: widget.eventKey,
      );
      final comments = await events.loadComments(
        eventId: widget.eventId,
        accessKey: widget.eventKey,
      );

      if (!mounted) return;
      setState(() {
        _detail = detail;
        _comments = comments;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final config = ref.watch(appConfigProvider);
    final apiUrl = config.apiUrl;
    final authState = ref.watch(authControllerProvider).state;
    final inAdminRoute =
        GoRouterState.of(context).uri.path.startsWith('/space_app/admin/');
    final isAdmin = inAdminRoute ||
        (authState.user != null &&
            config.adminTelegramIds.contains(authState.user!.telegramId));
    final detailAccessKey = detail == null
        ? (widget.eventKey ?? '').trim()
        : (detail.event.accessKey.trim().isNotEmpty
            ? detail.event.accessKey.trim()
            : (widget.eventKey ?? '').trim());
    final sanitizedDescription =
        detail == null ? '' : _stripCoordinatesText(detail.event.description);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали события'),
        actions: [
          if (isAdmin && detail != null)
            IconButton(
              tooltip: 'Удалить событие',
              onPressed: _deletingEvent
                  ? null
                  : () => _deleteEvent(eventId: detail.event.id),
              icon: _deletingEvent
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined),
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const PremiumLoadingView(
              text: 'EVENT DETAILS • LOADING • ',
              subtitle: 'Загружаем карточку события',
            )
          : (_error != null)
              ? Center(child: Text(_error!))
              : (detail == null)
                  ? const Center(child: Text('Событие не найдено'))
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        Text(
                          detail.event.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(formatDateTime(detail.event.startsAt)),
                        if (detail.event.endsAt != null)
                          Text(
                              'Завершение: ${formatDateTime(detail.event.endsAt)}'),
                        const SizedBox(height: 10),
                        if (detail.media.isNotEmpty)
                          SizedBox(
                            height: 210,
                            child: PageView.builder(
                              itemCount: detail.media.length,
                              itemBuilder: (context, index) {
                                final fallbackUrl = detail.media[index].trim();
                                final proxyUrl = buildEventMediaProxyUrl(
                                  apiUrl: apiUrl,
                                  eventId: detail.event.id,
                                  index: index,
                                  accessKey: detailAccessKey,
                                );
                                final imageUrl = proxyUrl.isNotEmpty
                                    ? proxyUrl
                                    : fallbackUrl;
                                final fallbackImageUrl =
                                    proxyUrl.isNotEmpty ? fallbackUrl : '';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: imageUrl.isEmpty
                                        ? Container(
                                            color: const Color(0xFFE8F0F4),
                                            child: const Icon(
                                                Icons.broken_image_outlined),
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
                                                          Container(
                                                    color:
                                                        const Color(0xFFE8F0F4),
                                                    child: const Icon(Icons
                                                        .broken_image_outlined),
                                                  ),
                                                );
                                              }
                                              return Container(
                                                color: const Color(0xFFE8F0F4),
                                                child: const Icon(Icons
                                                    .broken_image_outlined),
                                              );
                                            },
                                          ),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (sanitizedDescription.isNotEmpty)
                          Text(sanitizedDescription),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                                label: Text(
                                    '👥 ${detail.event.participantsCount}')),
                            Chip(label: Text('❤️ ${detail.event.likesCount}')),
                            Chip(
                                label:
                                    Text('💬 ${detail.event.commentsCount}')),
                            if (detail.event.capacity != null)
                              Chip(
                                label: Text(
                                  '🎟️ ${(detail.event.capacity! - detail.event.participantsCount).clamp(0, 9999)}',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => showPurchaseTicketFlow(
                                  context,
                                  eventId: detail.event.id,
                                ),
                                child: const Text('КУПИТЬ билет'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _sharing ? null : _share,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Поделиться'),
                            ),
                          ],
                        ),
                        if (!detail.isJoined) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _joining
                                ? null
                                : () async {
                                    setState(() => _joining = true);
                                    try {
                                      final events =
                                          ref.read(eventsControllerProvider);
                                      await events.joinEvent(
                                        eventId: detail.event.id,
                                        accessKey: widget.eventKey,
                                      );
                                      await _load();
                                    } catch (error) {
                                      _showMessage('$error');
                                    } finally {
                                      if (mounted) {
                                        setState(() => _joining = false);
                                      }
                                    }
                                  },
                            child: Text(
                                _joining ? 'Выполняется…' : 'Присоединиться'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final lat = detail.event.lat;
                            final lng = detail.event.lng;
                            launchUrl(Uri.parse(
                                'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng'));
                          },
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Открыть на карте'),
                        ),
                        if (detail.isJoined) ...[
                          const SizedBox(height: 16),
                          _ContactsBlock(detail: detail),
                        ],
                        const SizedBox(height: 16),
                        Text('Комментарии',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_comments.isEmpty)
                          const Text('Комментариев пока нет')
                        else
                          ..._comments.map(
                            (comment) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(comment.userName),
                              subtitle: Text(comment.body),
                              trailing: isAdmin
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          formatDateTime(comment.createdAt),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                        IconButton(
                                          tooltip: 'Удалить комментарий',
                                          onPressed: _deletingCommentIds
                                                  .contains(comment.id)
                                              ? null
                                              : () => _deleteComment(
                                                  comment: comment),
                                          icon: _deletingCommentIds
                                                  .contains(comment.id)
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.delete_outline),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      formatDateTime(comment.createdAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 400,
                          decoration: const InputDecoration(
                              labelText: 'Добавить комментарий'),
                          onChanged: (value) => _commentInput = value,
                        ),
                        FilledButton(
                          onPressed: _sendingComment
                              ? null
                              : () async {
                                  final body = _commentInput.trim();
                                  if (body.isEmpty) {
                                    _showMessage(
                                        'Комментарий не может быть пустым');
                                    return;
                                  }

                                  setState(() => _sendingComment = true);
                                  try {
                                    await ref
                                        .read(eventsControllerProvider)
                                        .addComment(
                                          eventId: detail.event.id,
                                          body: body,
                                          accessKey: widget.eventKey,
                                        );
                                    _commentInput = '';
                                    await _load();
                                  } catch (error) {
                                    _showMessage('$error');
                                  } finally {
                                    if (mounted) {
                                      setState(() => _sendingComment = false);
                                    }
                                  }
                                },
                          child:
                              Text(_sendingComment ? 'Отправка…' : 'Отправить'),
                        ),
                        if (detail.isJoined) ...[
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _joining
                                ? null
                                : () async {
                                    setState(() => _joining = true);
                                    try {
                                      await ref
                                          .read(eventsControllerProvider)
                                          .leaveEvent(
                                            eventId: detail.event.id,
                                            accessKey: widget.eventKey,
                                          );
                                      await _load();
                                    } catch (error) {
                                      _showMessage('$error');
                                    } finally {
                                      if (mounted) {
                                        setState(() => _joining = false);
                                      }
                                    }
                                  },
                            child: Text(_joining ? 'Выполняется…' : 'Покинуть'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Участники',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        ...detail.participants.map((participant) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person_outline_rounded),
                              title: Text(participant.name),
                              subtitle:
                                  Text(formatDateTime(participant.joinedAt)),
                            )),
                      ],
                    ),
    );
  }

  Future<void> _share() async {
    final detail = _detail;
    if (detail == null) return;

    setState(() => _sharing = true);
    try {
      final events = ref.read(eventsControllerProvider);
      final config = ref.read(appConfigProvider);
      final refCode = await events.loadReferralCode();
      final accessKey = events.accessKeyFor(detail.event.id,
          fallback: detail.event.accessKey);

      final url = buildEventShareUrl(
        eventId: detail.event.id,
        eventKey: accessKey,
        refCode: refCode,
        botUsername: config.botUsername,
      );

      final text = 'Event: ${detail.event.title}\n$url';

      if (kIsWeb && config.botUsername.trim().isNotEmpty) {
        final tgShareUrl =
            'https://t.me/share/url?url=${Uri.encodeComponent(url)}&text=${Uri.encodeComponent('Event: ${detail.event.title}')}';
        TelegramWebAppBridge.openLink(tgShareUrl);
      } else {
        await Share.share(text, subject: detail.event.title);
      }
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  Future<void> _deleteEvent({required int eventId}) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить событие?'),
        content: const Text(
          'Событие будет удалено без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    setState(() => _deletingEvent = true);
    try {
      await ref
          .read(eventsControllerProvider)
          .deleteEventAsAdmin(eventId: eventId);
      if (!mounted) return;
      _showMessage('Событие удалено');
      Navigator.of(context).maybePop();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _deletingEvent = false);
      }
    }
  }

  Future<void> _deleteComment({required EventComment comment}) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить комментарий?'),
        content: const Text(
          'Комментарий будет удален без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    setState(() {
      _deletingCommentIds.add(comment.id);
    });
    try {
      await ref.read(eventsControllerProvider).deleteCommentAsAdmin(
            commentId: comment.id,
          );
      await _load();
      if (!mounted) return;
      _showMessage('Комментарий удален');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() {
          _deletingCommentIds.remove(comment.id);
        });
      }
    }
  }

  String _stripCoordinatesText(String description) {
    final coordinateLine =
        RegExp(r'^\s*-?\d{1,2}(?:\.\d+)?\s*,\s*-?\d{1,3}(?:\.\d+)?\s*$');
    final cleaned = description
        .split('\n')
        .where((line) {
          final normalized = line.trim();
          if (normalized.isEmpty) return false;
          final lower = normalized.toLowerCase();
          if (lower.startsWith('coordinates:')) return false;
          if (lower.startsWith('координаты:')) return false;
          if (lower.contains('openstreetmap.org/?mlat=')) return false;
          if (coordinateLine.hasMatch(normalized)) return false;
          return true;
        })
        .join('\n')
        .trim();
    return cleaned;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ContactsBlock extends StatelessWidget {
  const _ContactsBlock({required this.detail});

  final EventDetail detail;

  @override
  Widget build(BuildContext context) {
    final rows = <_ContactRowData>[
      _ContactRowData('Telegram', detail.event.contactTelegram),
      _ContactRowData('WhatsApp', detail.event.contactWhatsapp),
      _ContactRowData('WeChat', detail.event.contactWechat),
      _ContactRowData('Messenger', detail.event.contactFbMessenger),
      _ContactRowData('Snapchat', detail.event.contactSnapchat),
    ].where((item) => item.value.trim().isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Контакты', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        ...rows.map((row) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text(row.kind),
            subtitle: Text(row.value),
          );
        }),
      ],
    );
  }
}

class _ContactRowData {
  const _ContactRowData(this.kind, this.value);

  final String kind;
  final String value;
}
