import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/constants/event_filters.dart';
import '../../../core/models/event_comment.dart';
import '../../../core/models/event_detail.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/utils/event_media_url_utils.dart';
import '../../../core/utils/share_utils.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/copy_to_clipboard.dart';
import '../../../ui/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../tickets/data/ticketing_repository.dart';
import '../../tickets/presentation/purchase_ticket_flow.dart';
import '../application/events_controller.dart';
import '../data/events_repository.dart';

/// TODO handles t o d o.

// TODO(ui-migration): migrate details/comments/participants blocks to AppScaffold and App* components.
class EventDetailsScreen extends ConsumerStatefulWidget {
  /// EventDetailsScreen handles event details screen.
  const EventDetailsScreen({
    required this.eventId,
    this.eventKey,
    super.key,
  });

  final int eventId;
  final String? eventKey;

  /// createState creates state.

  @override
  ConsumerState<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

/// _EventDetailsScreenState represents event details screen state.

class _EventDetailsScreenState extends ConsumerState<EventDetailsScreen> {
  EventDetail? _detail;
  List<EventComment> _comments = <EventComment>[];
  String _commentInput = '';

  bool _loading = true;
  bool _joining = false;
  bool _liking = false;
  bool _sharing = false;
  bool _sendingComment = false;
  bool _deletingEvent = false;
  bool _updatingPriority = false;
  bool _updatingEvent = false;
  bool _hasAnyProducts = true;
  final Set<int> _deletingCommentIds = <int>{};
  String? _error;

  /// initState handles init state.

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// _load loads data from the underlying source.

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final events = ref.read(eventsControllerProvider);
      final detailFuture = events.loadEventDetail(
        eventId: widget.eventId,
        accessKey: widget.eventKey,
      );
      final commentsFuture = events.loadComments(
        eventId: widget.eventId,
        accessKey: widget.eventKey,
      );
      final hasAnyProductsFuture = _loadProductsAvailability(widget.eventId);

      final detail = await detailFuture;
      final comments = await commentsFuture;
      final hasAnyProducts = await hasAnyProductsFuture;

      if (!mounted) return;
      setState(() {
        _detail = detail;
        _comments = comments;
        _hasAnyProducts = hasAnyProducts;
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

  /// _loadProductsAvailability loads products availability.

  Future<bool> _loadProductsAvailability(int eventId) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      return true;
    }

    try {
      final products =
          await ref.read(ticketingRepositoryProvider).getEventProducts(
                token: token,
                eventId: eventId,
              );
      return products.tickets.isNotEmpty || products.transfers.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final config = ref.watch(appConfigProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => _exitDetails(inAdminRoute: inAdminRoute),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Детали события'),
        actions: [
          if (isAdmin && detail != null)
            IconButton(
              tooltip: 'Редактировать событие',
              onPressed: _updatingEvent
                  ? null
                  : () => _editEventAsAdmin(detail: detail),
              icon: _updatingEvent
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
            ),
          if (isAdmin && detail != null)
            IconButton(
              tooltip: detail.event.isFeatured
                  ? 'Снять приоритет'
                  : 'Закрепить как ЛУЧШЕЕ СОБЫТИЕ',
              onPressed: _updatingPriority
                  ? null
                  : () => _togglePriority(detail: detail),
              icon: _updatingPriority
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      detail.event.isFeatured
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                    ),
            ),
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
          ? const SizedBox.shrink()
          : (_error != null)
              ? Center(child: Text(_error!))
              : (detail == null)
                  ? const Center(child: Text('Событие не найдено'))
                  : AppCard(
                      margin: const EdgeInsets.all(14),
                      variant: AppCardVariant.plain,
                      borderRadius: 20,
                      padding: EdgeInsets.zero,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.backgroundDeep.withValues(alpha: 0.28)
                              : AppColors.surfaceMuted.withValues(alpha: 0.3),
                        ),
                        child: ListView(
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
                                    final fallbackUrl =
                                        detail.media[index].trim();
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
                                                child: const Icon(Icons
                                                    .broken_image_outlined),
                                              )
                                            : Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, _, __) {
                                                  if (fallbackImageUrl
                                                          .isNotEmpty &&
                                                      fallbackImageUrl !=
                                                          imageUrl) {
                                                    return Image.network(
                                                      fallbackImageUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (context, _, __) =>
                                                              Container(
                                                        color: const Color(
                                                            0xFFE8F0F4),
                                                        child: const Icon(Icons
                                                            .broken_image_outlined),
                                                      ),
                                                    );
                                                  }
                                                  return Container(
                                                    color:
                                                        const Color(0xFFE8F0F4),
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
                                _buildLikeChip(detail: detail),
                                Chip(
                                    label: Text(
                                        '💬 ${detail.event.commentsCount}')),
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
                                    onPressed: _hasAnyProducts
                                        ? () => showPurchaseTicketFlow(
                                              context,
                                              eventId: detail.event.id,
                                            )
                                        : null,
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
                                          final events = ref
                                              .read(eventsControllerProvider);
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
                                child: Text(_joining
                                    ? 'Выполняется…'
                                    : 'Присоединиться'),
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
                                          setState(
                                              () => _sendingComment = false);
                                        }
                                      }
                                    },
                              child: Text(
                                  _sendingComment ? 'Отправка…' : 'Отправить'),
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
                                child: Text(
                                    _joining ? 'Выполняется…' : 'Покинуть'),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              'Участники',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            ...detail.participants
                                .map((participant) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                          Icons.person_outline_rounded),
                                      title: Text(participant.name),
                                      subtitle: Text(
                                          formatDateTime(participant.joinedAt)),
                                    )),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () =>
                                  _exitDetails(inAdminRoute: inAdminRoute),
                              icon: const Icon(Icons.home_outlined),
                              label:
                                  Text(inAdminRoute ? 'В админку' : 'В ленту'),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }

  /// _share handles internal share behavior.

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

  /// _buildLikeChip builds like chip.

  Widget _buildLikeChip({required EventDetail detail}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final likeAccent = theme.colorScheme.error;
    final liked = detail.event.isLiked;
    final backgroundColor = liked
        ? likeAccent.withValues(alpha: isDark ? 0.26 : 0.1)
        : (isDark
            ? AppColors.darkSurfaceMuted.withValues(alpha: 0.9)
            : AppColors.surfaceStrong);
    final borderColor = liked
        ? likeAccent.withValues(alpha: isDark ? 0.8 : 0.42)
        : (isDark ? AppColors.darkBorderStrong : AppColors.borderStrong);
    final labelColor = liked
        ? (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)
        : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary);

    return ActionChip(
      onPressed: _liking ? null : () => _toggleLike(detail: detail),
      backgroundColor: backgroundColor,
      side: BorderSide(color: borderColor),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: labelColor,
        fontWeight: liked ? FontWeight.w700 : FontWeight.w600,
      ),
      avatar: _liking
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(likeAccent),
              ),
            )
          : Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 16,
              color: liked ? likeAccent : labelColor,
            ),
      label: Text('${detail.event.likesCount}'),
    );
  }

  /// _toggleLike handles toggle like.

  Future<void> _toggleLike({required EventDetail detail}) async {
    setState(() => _liking = true);
    try {
      final events = ref.read(eventsControllerProvider);
      final accessKey = events.accessKeyFor(
        detail.event.id,
        fallback: detail.event.accessKey.trim().isNotEmpty
            ? detail.event.accessKey
            : widget.eventKey,
      );
      final status = await events.toggleLike(
        eventId: detail.event.id,
        isLiked: detail.event.isLiked,
        accessKey: accessKey,
      );
      if (!mounted) return;
      final current = _detail;
      if (current == null || current.event.id != detail.event.id) return;
      setState(() {
        _detail = current.copyWith(
          event: current.event.copyWith(
            likesCount: status.likesCount,
            isLiked: status.isLiked,
          ),
        );
      });
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _liking = false);
      }
    }
  }

  /// _togglePriority handles toggle priority.

  Future<void> _togglePriority({required EventDetail detail}) async {
    final enable = !detail.event.isFeatured;
    setState(() => _updatingPriority = true);
    try {
      await ref.read(eventsControllerProvider).setFeedPriorityAsAdmin(
            eventId: detail.event.id,
            enabled: enable,
          );
      await _load();
      if (!mounted) return;
      _showMessage(
        enable
            ? 'Событие закреплено как ЛУЧШЕЕ СОБЫТИЕ'
            : 'Приоритет события снят',
      );
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _updatingPriority = false);
      }
    }
  }

  /// _editEventAsAdmin handles edit event as admin.

  Future<void> _editEventAsAdmin({required EventDetail detail}) async {
    final submission = await _showAdminEditDialog(detail: detail);
    if (submission == null) return;

    setState(() => _updatingEvent = true);
    try {
      await ref.read(eventsControllerProvider).updateEventAsAdmin(
            eventId: detail.event.id,
            payload: submission.toPayload(),
          );
      await _load();
      if (!mounted) return;
      _showMessage('Событие обновлено');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _updatingEvent = false);
      }
    }
  }

  /// _showAdminEditDialog handles show admin edit dialog.

  Future<_AdminEventEditSubmission?> _showAdminEditDialog({
    required EventDetail detail,
  }) async {
    final titleCtrl = TextEditingController(text: detail.event.title);
    final descriptionCtrl =
        TextEditingController(text: detail.event.description);
    final startsAtCtrl =
        TextEditingController(text: _formatIsoInput(detail.event.startsAt));
    final endsAtCtrl =
        TextEditingController(text: _formatIsoInput(detail.event.endsAt));
    final latCtrl =
        TextEditingController(text: detail.event.lat.toStringAsFixed(6));
    final lngCtrl =
        TextEditingController(text: detail.event.lng.toStringAsFixed(6));
    final capacityCtrl =
        TextEditingController(text: detail.event.capacity?.toString() ?? '');
    final contactTelegramCtrl =
        TextEditingController(text: detail.event.contactTelegram);
    final contactWhatsappCtrl =
        TextEditingController(text: detail.event.contactWhatsapp);
    final contactWechatCtrl =
        TextEditingController(text: detail.event.contactWechat);
    final contactMessengerCtrl =
        TextEditingController(text: detail.event.contactFbMessenger);
    final contactSnapchatCtrl =
        TextEditingController(text: detail.event.contactSnapchat);
    final selectedFilters = <String>{...detail.event.filters};
    String? validationError;

    final result = await showDialog<_AdminEventEditSubmission>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _AdminEventEditSubmission? buildSubmission() {
              final title = titleCtrl.text.trim();
              if (title.isEmpty) {
                setDialogState(
                    () => validationError = 'Название не может быть пустым');
                return null;
              }
              if (_runeLength(title) > 80) {
                setDialogState(() => validationError =
                    'Название должно быть не длиннее 80 символов');
                return null;
              }

              final description = descriptionCtrl.text.trim();
              if (description.isEmpty) {
                setDialogState(
                    () => validationError = 'Описание не может быть пустым');
                return null;
              }
              if (_runeLength(description) > 1000) {
                setDialogState(() => validationError =
                    'Описание должно быть не длиннее 1000 символов');
                return null;
              }

              final startsAtRaw = startsAtCtrl.text.trim();
              final startsAt = DateTime.tryParse(startsAtRaw);
              if (startsAt == null) {
                setDialogState(() => validationError =
                    'Укажите корректный startsAt в ISO-формате');
                return null;
              }

              final endsAtRaw = endsAtCtrl.text.trim();
              DateTime? endsAt;
              var clearEndsAt = false;
              if (endsAtRaw.isEmpty) {
                clearEndsAt = detail.event.endsAt != null;
              } else {
                endsAt = DateTime.tryParse(endsAtRaw);
                if (endsAt == null) {
                  setDialogState(() => validationError =
                      'Укажите корректный endsAt в ISO-формате');
                  return null;
                }
              }
              if (endsAt != null && endsAt.isBefore(startsAt)) {
                setDialogState(() => validationError =
                    'Дата завершения должна быть позже начала');
                return null;
              }

              final lat = _parseCoordinate(latCtrl.text);
              final lng = _parseCoordinate(lngCtrl.text);
              if (lat == null || lng == null) {
                setDialogState(() =>
                    validationError = 'Укажите корректные координаты lat/lng');
                return null;
              }
              if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
                setDialogState(() =>
                    validationError = 'Координаты вне допустимого диапазона');
                return null;
              }

              final capacityRaw = capacityCtrl.text.trim();
              int? capacity;
              if (capacityRaw.isEmpty) {
                if (detail.event.capacity != null) {
                  setDialogState(() => validationError =
                      'Очистка лимита не поддерживается. Укажите число больше 0');
                  return null;
                }
              } else {
                capacity = int.tryParse(capacityRaw);
                if (capacity == null || capacity <= 0) {
                  setDialogState(() => validationError =
                      'Лимит участников должен быть целым числом больше 0');
                  return null;
                }
              }

              if (selectedFilters.length > kMaxEventFilters) {
                setDialogState(() => validationError =
                    'Можно выбрать максимум $kMaxEventFilters фильтра');
                return null;
              }

              final contactTelegram = contactTelegramCtrl.text.trim();
              final contactWhatsapp = contactWhatsappCtrl.text.trim();
              final contactWechat = contactWechatCtrl.text.trim();
              final contactMessenger = contactMessengerCtrl.text.trim();
              final contactSnapchat = contactSnapchatCtrl.text.trim();

              if (_runeLength(contactTelegram) > 120 ||
                  _runeLength(contactWhatsapp) > 120 ||
                  _runeLength(contactWechat) > 120 ||
                  _runeLength(contactMessenger) > 120 ||
                  _runeLength(contactSnapchat) > 120) {
                setDialogState(() => validationError =
                    'Контакт не должен превышать 120 символов');
                return null;
              }

              setDialogState(() => validationError = null);
              return _AdminEventEditSubmission(
                title: title,
                description: description,
                startsAt: startsAt,
                endsAt: endsAt,
                clearEndsAt: clearEndsAt,
                lat: lat,
                lng: lng,
                capacity: capacity,
                filters: selectedFilters.toList(growable: false),
                contactTelegram: contactTelegram,
                contactWhatsapp: contactWhatsapp,
                contactWechat: contactWechat,
                contactFbMessenger: contactMessenger,
                contactSnapchat: contactSnapchat,
              );
            }

            return AlertDialog(
              title: const Text('Редактировать событие'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        maxLength: 80,
                        decoration:
                            const InputDecoration(labelText: 'Название'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descriptionCtrl,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 1000,
                        decoration:
                            const InputDecoration(labelText: 'Описание'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: startsAtCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Начало (ISO)',
                          hintText: '2026-03-18T19:00:00Z',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: endsAtCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Окончание (ISO, пусто = убрать)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration:
                                  const InputDecoration(labelText: 'Lat'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: lngCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration:
                                  const InputDecoration(labelText: 'Lng'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Лимит участников',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Теги (${selectedFilters.length}/$kMaxEventFilters)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kEventFilters.map((filter) {
                          final active = selectedFilters.contains(filter.id);
                          return FilterChip(
                            selected: active,
                            label: Text('${filter.icon} ${filter.label}'),
                            onSelected: (selected) {
                              setDialogState(() {
                                validationError = null;
                                if (selected) {
                                  if (!active &&
                                      selectedFilters.length >=
                                          kMaxEventFilters) {
                                    validationError =
                                        'Можно выбрать максимум $kMaxEventFilters фильтра';
                                    return;
                                  }
                                  selectedFilters.add(filter.id);
                                } else {
                                  selectedFilters.remove(filter.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: contactTelegramCtrl,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Telegram @username',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: contactWhatsappCtrl,
                        maxLength: 120,
                        decoration:
                            const InputDecoration(labelText: 'WhatsApp'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: contactWechatCtrl,
                        maxLength: 120,
                        decoration: const InputDecoration(labelText: 'WeChat'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: contactMessengerCtrl,
                        maxLength: 120,
                        decoration:
                            const InputDecoration(labelText: 'Messenger'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: contactSnapchatCtrl,
                        maxLength: 120,
                        decoration:
                            const InputDecoration(labelText: 'Snapchat'),
                      ),
                      if ((validationError ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    final submission = buildSubmission();
                    if (submission == null) return;
                    Navigator.of(dialogContext).pop(submission);
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    startsAtCtrl.dispose();
    endsAtCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
    capacityCtrl.dispose();
    contactTelegramCtrl.dispose();
    contactWhatsappCtrl.dispose();
    contactWechatCtrl.dispose();
    contactMessengerCtrl.dispose();
    contactSnapchatCtrl.dispose();

    return result;
  }

  /// _deleteEvent deletes event.

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

  /// _deleteComment deletes comment.

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

  /// _stripCoordinatesText handles strip coordinates text.

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

  /// _formatIsoInput formats iso input.

  String _formatIsoInput(DateTime? value) {
    if (value == null) return '';
    return value.toUtc().toIso8601String();
  }

  /// _parseCoordinate parses coordinate.

  double? _parseCoordinate(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  /// _runeLength handles rune length.

  int _runeLength(String value) => value.runes.length;

  /// _exitDetails handles exit details.

  void _exitDetails({required bool inAdminRoute}) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(inAdminRoute ? AppRoutes.admin : AppRoutes.feed);
  }

  /// _showMessage handles show message.

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// _AdminEventEditSubmission represents admin event edit submission.

class _AdminEventEditSubmission {
  /// _AdminEventEditSubmission handles admin event edit submission.
  _AdminEventEditSubmission({
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.clearEndsAt,
    required this.lat,
    required this.lng,
    required this.capacity,
    required this.filters,
    required this.contactTelegram,
    required this.contactWhatsapp,
    required this.contactWechat,
    required this.contactFbMessenger,
    required this.contactSnapchat,
  });

  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool clearEndsAt;
  final double lat;
  final double lng;
  final int? capacity;
  final List<String> filters;
  final String contactTelegram;
  final String contactWhatsapp;
  final String contactWechat;
  final String contactFbMessenger;
  final String contactSnapchat;

  /// toPayload handles to payload.

  UpdateEventAdminPayload toPayload() {
    return UpdateEventAdminPayload(
      title: title,
      description: description,
      startsAt: startsAt,
      endsAt: endsAt,
      clearEndsAt: clearEndsAt,
      lat: lat,
      lng: lng,
      capacity: capacity,
      filters: filters,
      contactTelegram: contactTelegram,
      contactWhatsapp: contactWhatsapp,
      contactWechat: contactWechat,
      contactFbMessenger: contactFbMessenger,
      contactSnapchat: contactSnapchat,
    );
  }
}

/// _ContactsBlock represents contacts block.

class _ContactsBlock extends StatelessWidget {
  /// _ContactsBlock handles contacts block.
  const _ContactsBlock({required this.detail});

  final EventDetail detail;

  /// build renders the widget tree for this component.

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
            subtitle: SelectableText(row.value),
            trailing: IconButton(
              tooltip: 'Скопировать',
              onPressed: () => copyToClipboard(
                context,
                text: row.value,
                successMessage: '${row.kind} скопирован',
              ),
              icon: const Icon(Icons.copy_rounded),
            ),
          );
        }),
      ],
    );
  }
}

/// _ContactRowData represents contact row data.

class _ContactRowData {
  /// _ContactRowData handles contact row data.
  const _ContactRowData(this.kind, this.value);

  final String kind;
  final String value;
}
