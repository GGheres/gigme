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
import '../features/tickets/presentation/admin_order_detail_page.dart';
import '../features/tickets/presentation/admin_orders_page.dart';
import '../features/tickets/presentation/admin_products_page.dart';
import '../features/tickets/presentation/admin_promo_codes_page.dart';
import '../features/tickets/presentation/admin_qr_scanner_page.dart';
import '../features/tickets/presentation/admin_stats_page.dart';
import '../features/tickets/presentation/my_tickets_page.dart';
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

String? _readAuthNext(Uri authUri) {
  final raw = authUri.queryParameters['next']?.trim() ?? '';
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

Page<void> _noTransitionPage(
  GoRouterState state,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}
