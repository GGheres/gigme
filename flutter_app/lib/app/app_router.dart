import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/landing/presentation/landing_screen.dart';
import '../features/admin/presentation/admin_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/dev/presentation/ui_preview_screen.dart';
import '../features/events/presentation/create_event_screen.dart';
import '../features/events/presentation/event_details_screen.dart';
import '../features/events/presentation/feed_screen.dart';
import '../features/events/presentation/map_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/settings_screen.dart';
import '../features/tickets/presentation/admin_order_detail_page.dart';
import '../features/tickets/presentation/admin_orders_page.dart';
import '../features/tickets/presentation/admin_bot_messages_page.dart';
import '../features/tickets/presentation/admin_products_page.dart';
import '../features/tickets/presentation/admin_promo_codes_page.dart';
import '../features/tickets/presentation/admin_qr_scanner_page.dart';
import '../features/tickets/presentation/admin_stats_page.dart';
import '../features/tickets/presentation/my_tickets_page.dart';
import '../ui/layout/landing_backdrop.dart';
import 'app_shell.dart';
import 'routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authControllerProvider);

  return GoRouter(
    initialLocation: AppRoutes.landing,
    refreshListenable: auth,
    redirect: (context, state) {
      final status = auth.state.status;
      final location = state.matchedLocation;

      if (location == AppRoutes.landing && status != AuthStatus.loading) {
        final startup = auth.consumeStartupLink();
        final startupLocation = _startupEventLocation(
          eventId: startup?.eventId,
          eventKey: startup?.eventKey,
          refCode: startup?.refCode,
        );
        if (startupLocation != null) {
          if (status == AuthStatus.authenticated) {
            return startupLocation;
          }
          return _authRouteWithNext(
            targetUri: Uri.parse(startupLocation),
            alreadyInAuth: false,
          );
        }
      }

      if (!AppRoutes.isAppPath(location)) {
        return null;
      }

      final isAdminRoute = location.startsWith(AppRoutes.admin);

      if (location == AppRoutes.appRoot) {
        if (status == AuthStatus.authenticated) {
          return AppRoutes.feed;
        }
        return AppRoutes.auth;
      }

      final inAuth = location == AppRoutes.auth;
      final redirectToAuthWithNext =
          _authRouteWithNext(targetUri: state.uri, alreadyInAuth: inAuth);

      if (status == AuthStatus.loading) {
        if (isAdminRoute) return null;
        return redirectToAuthWithNext;
      }

      if (status == AuthStatus.unauthenticated) {
        if (isAdminRoute) return null;
        return redirectToAuthWithNext;
      }

      if (status == AuthStatus.authenticated && inAuth) {
        final next = _readAuthNext(state.uri);
        return next ?? AppRoutes.feed;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.landing,
        pageBuilder: (context, state) =>
            _noTransitionPage(state, const LandingScreen()),
      ),
      GoRoute(
        path: AppRoutes.appRoot,
        redirect: (context, state) {
          final status = auth.state.status;
          if (status == AuthStatus.authenticated) {
            return AppRoutes.feed;
          }
          return AppRoutes.auth;
        },
      ),
      GoRoute(
        path: AppRoutes.auth,
        pageBuilder: (context, state) =>
            _noTransitionPage(state, const AuthScreen()),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => _noTransitionPage(
          state,
          AppShell(navigationShell: navigationShell),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.feed,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const FeedScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.map,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const MapScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.create,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const CreateEventScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const ProfileScreen()),
              ),
              GoRoute(
                path: AppRoutes.settings,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const SettingsScreen()),
              ),
              GoRoute(
                path: AppRoutes.uiPreview,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const UiPreviewScreen()),
              ),
              GoRoute(
                path: AppRoutes.myTickets,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const MyTicketsPage()),
              ),
              GoRoute(
                path: AppRoutes.admin,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const AdminScreen()),
              ),
              GoRoute(
                path: AppRoutes.adminOrders,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const AdminOrdersPage()),
              ),
              GoRoute(
                path: AppRoutes.adminBotMessages,
                pageBuilder: (context, state) => _noTransitionPage(
                  state,
                  AdminBotMessagesPage(
                    initialChatId: int.tryParse(
                      state.uri.queryParameters['chatId'] ??
                          state.uri.queryParameters['chat_id'] ??
                          '',
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/space_app/admin/orders/:id',
                pageBuilder: (context, state) => _noTransitionPage(
                  state,
                  AdminOrderDetailPage(
                    orderId: state.pathParameters['id'] ?? '',
                  ),
                ),
              ),
              GoRoute(
                path: AppRoutes.adminScanner,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const AdminQrScannerPage()),
              ),
              GoRoute(
                path: AppRoutes.adminProducts,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const AdminProductsPage()),
              ),
              GoRoute(
                path: AppRoutes.adminPromos,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const AdminPromoCodesPage()),
              ),
              GoRoute(
                path: AppRoutes.adminStats,
                pageBuilder: (context, state) =>
                    _noTransitionPage(state, const AdminStatsPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/space_app/event/:id',
        pageBuilder: (context, state) {
          final eventId = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _noTransitionPage(
            state,
            EventDetailsScreen(
              eventId: eventId,
              eventKey: state.uri.queryParameters['key'] ??
                  state.uri.queryParameters['eventKey'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/space_app/admin/event/:id',
        pageBuilder: (context, state) {
          final eventId = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _noTransitionPage(
            state,
            EventDetailsScreen(
              eventId: eventId,
              eventKey: state.uri.queryParameters['key'] ??
                  state.uri.queryParameters['eventKey'],
            ),
          );
        },
      ),
    ],
  );
});

/// _authRouteWithNext authenticates route with next.

String? _authRouteWithNext({
  required Uri targetUri,
  required bool alreadyInAuth,
}) {
  if (alreadyInAuth) return null;
  final next = _normalizeAppLocation(targetUri);
  if (next == null || next == AppRoutes.auth) {
    return AppRoutes.auth;
  }
  return Uri(path: AppRoutes.auth, queryParameters: {'next': next}).toString();
}

/// _readAuthNext reads auth next.

String? _readAuthNext(Uri authUri) {
  final rawQueryNext = authUri.queryParameters['next']?.trim() ?? '';
  final rawState = _extractStateFromAuthUri(authUri)?.trim() ?? '';
  final rawStateNext = _extractNextFromSignedVKState(rawState) ?? '';
  final raw = rawQueryNext.isNotEmpty
      ? rawQueryNext
      : (rawStateNext.isNotEmpty ? rawStateNext : rawState);
  if (raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return null;
  final path = parsed.path.trim();
  if (!AppRoutes.isAppPath(path) || path == AppRoutes.auth) {
    return null;
  }
  var out = path;
  if (parsed.hasQuery) {
    out = '$out?${parsed.query}';
  }
  if (parsed.fragment.isNotEmpty) {
    out = '$out#${parsed.fragment}';
  }
  return out;
}

/// _extractStateFromAuthUri extracts state from auth uri.

String? _extractStateFromAuthUri(Uri authUri) {
  final fromQuery = authUri.queryParameters['state']?.trim() ?? '';
  if (fromQuery.isNotEmpty) return fromQuery;

  final fragment = authUri.fragment.trim();
  if (fragment.isEmpty) return null;

  final candidates = <String>{fragment};
  final questionMarkIndex = fragment.indexOf('?');
  if (questionMarkIndex >= 0 && questionMarkIndex < fragment.length - 1) {
    candidates.add(fragment.substring(questionMarkIndex + 1));
  }

  for (final candidate in candidates) {
    try {
      final params = Uri.splitQueryString(candidate);
      final fromHash = params['state']?.trim() ?? '';
      if (fromHash.isNotEmpty) return fromHash;
    } catch (_) {
      // Ignore malformed fragments and keep auth redirect flow.
    }
  }

  return null;
}

/// _extractNextFromSignedVKState extracts next from signed v k state.

String? _extractNextFromSignedVKState(String state) {
  final raw = state.trim();
  if (raw.isEmpty) return null;

  final parts = raw.split('.');
  if (parts.length != 2 || parts.first.isEmpty) {
    return null;
  }

  try {
    final normalized = _normalizeBase64(parts.first);
    final payloadRaw = utf8.decode(base64.decode(normalized));
    final payload = jsonDecode(payloadRaw);
    if (payload is! Map) return null;

    final next = payload['n']?.toString().trim() ?? '';
    if (next.isEmpty) return null;
    return next;
  } catch (_) {
    return null;
  }
}

/// _normalizeBase64 normalizes base64.

String _normalizeBase64(String source) {
  final normalized = source.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  if (remainder == 0) {
    return normalized;
  }
  return normalized.padRight(normalized.length + (4 - remainder), '=');
}

/// _normalizeAppLocation normalizes app location.

String? _normalizeAppLocation(Uri uri) {
  final path = uri.path.trim();
  if (!AppRoutes.isAppPath(path)) {
    return null;
  }
  var out = path;
  if (uri.hasQuery) {
    out = '$out?${uri.query}';
  }
  if (uri.fragment.isNotEmpty) {
    out = '$out#${uri.fragment}';
  }
  return out;
}

/// _startupEventLocation handles startup event location.

String? _startupEventLocation({
  required int? eventId,
  required String? eventKey,
  required String? refCode,
}) {
  if (eventId == null || eventId <= 0) return null;

  final safeKey = (eventKey ?? '').trim();
  final safeRef = (refCode ?? '').trim();

  final uri = Uri(
    path: AppRoutes.event(eventId),
    queryParameters: {
      if (safeKey.isNotEmpty) 'key': safeKey,
      if (safeRef.isNotEmpty) 'ref': safeRef,
    },
  );
  return uri.toString();
}

/// _noTransitionPage handles no transition page.

Page<void> _noTransitionPage(
  GoRouterState state,
  Widget child,
) {
  final shouldUseLandingBackdropOnWeb =
      kIsWeb && state.matchedLocation != AppRoutes.landing;

  if (shouldUseLandingBackdropOnWeb) {
    return NoTransitionPage<void>(
      key: state.pageKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: LandingBackdrop()),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}
