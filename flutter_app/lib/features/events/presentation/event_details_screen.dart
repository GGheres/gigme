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
import '../../../core/utils/share_utils.dart';
import '../../../integrations/telegram/telegram_web_app_bridge.dart';
import '../application/events_controller.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/feed');
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text('Event details'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : (detail == null)
                  ? const Center(child: Text('Event not found'))
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
                          Text('Ends: ${formatDateTime(detail.event.endsAt)}'),
                        const SizedBox(height: 10),
                        if (detail.media.isNotEmpty)
                          SizedBox(
                            height: 210,
                            child: PageView.builder(
                              itemCount: detail.media.length,
                              itemBuilder: (context, index) {
                                final url = detail.media[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, _, __) => Container(
                                        color: const Color(0xFFE8F0F4),
                                        child: const Icon(Icons.broken_image_outlined),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(detail.event.description),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('${detail.event.participantsCount} going')),
                            Chip(label: Text('${detail.event.likesCount} likes')),
                            Chip(label: Text('${detail.event.commentsCount} comments')),
                            if (detail.event.capacity != null)
                              Chip(
                                label: Text(
                                  '${(detail.event.capacity! - detail.event.participantsCount).clamp(0, 9999)} spots left',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _joining
                                    ? null
                                    : () async {
                                        setState(() => _joining = true);
                                        try {
                                          final events = ref.read(eventsControllerProvider);
                                          if (detail.isJoined) {
                                            await events.leaveEvent(
                                              eventId: detail.event.id,
                                              accessKey: widget.eventKey,
                                            );
                                          } else {
                                            await events.joinEvent(
                                              eventId: detail.event.id,
                                              accessKey: widget.eventKey,
                                            );
                                          }
                                          await _load();
                                        } catch (error) {
                                          _showMessage('$error');
                                        } finally {
                                          if (mounted) {
                                            setState(() => _joining = false);
                                          }
                                        }
                                      },
                                child: Text(detail.isJoined ? 'Leave event' : 'Join event'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _sharing ? null : _share,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Share'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final lat = detail.event.lat;
                            final lng = detail.event.lng;
                            launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng'));
                          },
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Open location on map'),
                        ),
                        if (detail.isJoined) ...[
                          const SizedBox(height: 16),
                          _ContactsBlock(detail: detail),
                        ],
                        const SizedBox(height: 16),
                        Text('Comments', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_comments.isEmpty)
                          const Text('No comments yet')
                        else
                          ..._comments.map(
                            (comment) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(comment.userName),
                              subtitle: Text(comment.body),
                              trailing: Text(
                                formatDateTime(comment.createdAt),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 400,
                          decoration: const InputDecoration(labelText: 'Add comment'),
                          onChanged: (value) => _commentInput = value,
                        ),
                        FilledButton(
                          onPressed: _sendingComment
                              ? null
                              : () async {
                                  final body = _commentInput.trim();
                                  if (body.isEmpty) {
                                    _showMessage('Comment cannot be empty');
                                    return;
                                  }

                                  setState(() => _sendingComment = true);
                                  try {
                                    await ref.read(eventsControllerProvider).addComment(
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
                          child: Text(_sendingComment ? 'Sending…' : 'Send comment'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Participants',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        ...detail.participants.map((participant) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person_outline_rounded),
                              title: Text(participant.name),
                              subtitle: Text(formatDateTime(participant.joinedAt)),
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
      final accessKey = events.accessKeyFor(detail.event.id, fallback: detail.event.accessKey);

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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
        Text('Contacts', style: Theme.of(context).textTheme.titleMedium),
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
