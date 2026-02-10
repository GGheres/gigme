import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/landing_repository.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  bool _loading = false;
  String? _error;
  List<LandingEvent> _events = <LandingEvent>[];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter(_events);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFFFF3E0),
              Color(0xFFE3F2FD),
              Color(0xFFE8F5E9),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                _HeroHeader(
                  total: _total,
                  onOpenApp: () => context.go(AppRoutes.appRoot),
                  onRefresh: _loading ? null : _load,
                ),
                const SizedBox(height: 14),
                if ((_error ?? '').trim().isNotEmpty)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                const SizedBox(height: 8),
                _MapSection(
                  loading: _loading,
                  events: _events,
                  center: center,
                  onEventTap: (event) => _showEventSheet(event),
                ),
                const SizedBox(height: 14),
                Text(
                  'Афиша событий',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (!_loading && _events.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('События пока не опубликованы'),
                    ),
                  )
                else
                  ..._events.map(
                    (event) => _LandingEventCard(
                      event: event,
                      onOpenEvent: () => _openApp(event),
                      onBuy: () => _openTicket(event),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ref
          .read(landingRepositoryProvider)
          .listEvents(limit: 100, offset: 0);
      if (!mounted) return;
      setState(() {
        _events = response.items;
        _total = response.total;
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

  Future<void> _openTicket(LandingEvent event) async {
    final rawUrl =
        event.ticketUrl.trim().isNotEmpty ? event.ticketUrl : event.appUrl;
    if (rawUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openApp(LandingEvent event) async {
    final rawUrl = event.appUrl.trim();
    if (rawUrl.isEmpty) {
      context.go(AppRoutes.appRoot);
      return;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      context.go(AppRoutes.appRoot);
      return;
    }

    final localPath = _localAppPath(uri);
    final authStatus = ref.read(authControllerProvider).state.status;
    if (localPath != null && authStatus == AuthStatus.authenticated) {
      context.go(localPath);
      return;
    }

    final target = uri.hasScheme ? uri : Uri.base.resolveUri(uri);
    await launchUrl(target, mode: LaunchMode.platformDefault);
  }

  Future<void> _showEventSheet(LandingEvent event) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(formatDateTime(event.startsAt)),
              if (event.addressLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(event.addressLabel.trim()),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(_openTicket(event));
                },
                icon: const Icon(Icons.confirmation_number_outlined),
                label: const Text('Купить билет'),
              ),
            ],
          ),
        );
      },
    );
  }
}

String? _localAppPath(Uri uri) {
  if (uri.path.isEmpty || !uri.path.startsWith(AppRoutes.appRoot)) {
    return null;
  }
  if (uri.host.isNotEmpty) {
    final current = Uri.base;
    if (uri.host != current.host || uri.scheme != current.scheme) {
      return null;
    }
  }

  var out = uri.path;
  if (uri.hasQuery) {
    out = '$out?${uri.query}';
  }
  if (uri.fragment.isNotEmpty) {
    out = '$out#${uri.fragment}';
  }
  return out;
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.total,
    required this.onOpenApp,
    required this.onRefresh,
  });

  final int total;
  final VoidCallback onOpenApp;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0D47A1), Color(0xFF00695C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SPACEFESTIVAL',
            style: TextStyle(
              color: Colors.white70,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Лендинг событий',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Опубликовано: $total',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0D47A1),
                ),
                onPressed: onOpenApp,
                child: const Text('Открыть Space App'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
                onPressed: onRefresh,
                child: const Text('Обновить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapSection extends StatelessWidget {
  const _MapSection({
    required this.loading,
    required this.events,
    required this.center,
    required this.onEventTap,
  });

  final bool loading;
  final List<LandingEvent> events;
  final LatLng center;
  final ValueChanged<LandingEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 11,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'gigme_flutter',
                ),
                MarkerLayer(
                  markers: [
                    for (final event in events)
                      Marker(
                        width: 44,
                        height: 44,
                        point: LatLng(event.lat, event.lng),
                        child: InkWell(
                          onTap: () => onEventTap(event),
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF6C00),
                              border: Border.all(color: Colors.white, width: 2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (loading)
              const Positioned(
                top: 12,
                right: 12,
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _LandingEventCard extends StatelessWidget {
  const _LandingEventCard({
    required this.event,
    required this.onOpenEvent,
    required this.onBuy,
  });

  final LandingEvent event;
  final VoidCallback onOpenEvent;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 108,
                height: 108,
                child: event.thumbnailUrl.trim().isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFE3EDF7),
                        child: Icon(Icons.image_outlined),
                      )
                    : Image.network(
                        event.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, __) => const ColoredBox(
                          color: Color(0xFFE3EDF7),
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatDateTime(event.startsAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (event.addressLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.addressLabel.trim(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    event.description.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: onBuy,
                        icon: const Icon(Icons.confirmation_number_outlined),
                        label: const Text('Купить билет'),
                      ),
                      OutlinedButton(
                        onPressed: onOpenEvent,
                        child: const Text('Открыть в app'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

LatLng _mapCenter(List<LandingEvent> events) {
  if (events.isEmpty) return const LatLng(55.751244, 37.618423);
  var sumLat = 0.0;
  var sumLng = 0.0;
  for (final event in events) {
    sumLat += event.lat;
    sumLng += event.lng;
  }
  return LatLng(sumLat / events.length, sumLng / events.length);
}
