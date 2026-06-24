import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/models/event_card.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_states.dart';
import '../../../ui/components/screen_hero.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_spacing.dart';
import '../../events/application/events_controller.dart';
import '../../events/application/location_controller.dart';
import 'purchase_ticket_flow.dart';

/// PurchaseEntryScreen resolves generic bot menu links to a concrete event flow.
class PurchaseEntryScreen extends ConsumerStatefulWidget {
  /// PurchaseEntryScreen handles generic purchase or transfer entry.
  const PurchaseEntryScreen({
    required this.mode,
    super.key,
  });

  final PurchaseFlowMode mode;

  /// createState creates state.
  @override
  ConsumerState<PurchaseEntryScreen> createState() =>
      _PurchaseEntryScreenState();
}

/// _PurchaseEntryScreenState represents purchase entry state.
class _PurchaseEntryScreenState extends ConsumerState<PurchaseEntryScreen> {
  bool _resolving = false;
  bool _scheduled = false;
  String? _error;

  bool get _isTransferMode => widget.mode == PurchaseFlowMode.transfer;

  String get _title =>
      _isTransferMode ? 'Открываем трансфер' : 'Открываем покупку билета';

  String get _emptyTitle =>
      _isTransferMode ? 'Трансфер пока недоступен' : 'Билеты пока недоступны';

  /// build renders the widget tree for this component.
  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider).state;
    final events = ref.watch(eventsControllerProvider).state;

    if (!_scheduled && !location.loading) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_resolveEvent());
      });
    }

    final loading = location.loading || _resolving || events.loading;
    return AppScaffold(
      appBar: AppBar(
        title: Text(_title),
        leading: IconButton(
          onPressed: _goBackToApp,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: loading
              ? LoadingState(
                  title: _title,
                  subtitle: 'Подбираем ближайшее доступное событие',
                )
              : _error == null
                  ? _EntryFallback(
                      title: _emptyTitle,
                      subtitle:
                          'Откройте ленту SPACE APP и выберите событие вручную.',
                      onBack: _goBackToApp,
                      onRetry: _retry,
                    )
                  : ErrorState(
                      message: _error!,
                      onRetry: _retry,
                    ),
        ),
      ),
    );
  }

  /// _resolveEvent loads the feed and redirects to the selected purchase route.
  Future<void> _resolveEvent() async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _error = null;
    });

    try {
      final location = ref.read(locationControllerProvider).state;
      final eventsController = ref.read(eventsControllerProvider);
      if (eventsController.state.feed.isEmpty) {
        await eventsController.refresh(
          center: location.center,
          forceLoading: true,
        );
      }
      if (!mounted) return;

      final event = _selectEvent(eventsController.state.feed);
      if (event == null) {
        setState(() {
          _resolving = false;
          _error = null;
        });
        return;
      }

      final target = _isTransferMode
          ? AppRoutes.eventTransferPurchase(event.id)
          : AppRoutes.eventPurchase(event.id);
      context.go(target);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = '$error';
      });
    }
  }

  /// _selectEvent picks the next visible event from the already sorted feed.
  EventCard? _selectEvent(List<EventCard> feed) {
    final now = DateTime.now();
    for (final event in feed) {
      final startsAt = event.startsAt;
      if (startsAt == null || startsAt.isAfter(now)) {
        return event;
      }
    }
    if (feed.isEmpty) return null;
    return feed.first;
  }

  /// _retry restarts event resolution after a failed feed load.
  void _retry() {
    setState(() {
      _scheduled = false;
      _error = null;
    });
  }

  /// _goBackToApp returns users to a stable app section on iOS and Android.
  void _goBackToApp() {
    context.go(AppRoutes.feed);
  }
}

/// _EntryFallback represents a friendly empty state for generic bot links.
class _EntryFallback extends StatelessWidget {
  /// _EntryFallback handles empty generic purchase entry.
  const _EntryFallback({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  /// build renders the widget tree for this component.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScreenHero(
          title: title,
          subtitle: subtitle,
          actions: [
            PrimaryButton(
              label: 'Назад в SPACE APP',
              onPressed: onBack,
            ),
            SecondaryButton(
              label: 'Повторить',
              outline: true,
              onPressed: onRetry,
            ),
          ],
        ),
      ],
    );
  }
}
