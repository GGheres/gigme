import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/landing/presentation/landing_screen.dart';
import '../features/admin/presentation/admin_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_state.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/events/presentation/create_event_screen.dart';
import '../features/events/presentation/event_details_screen.dart';
import '../features/events/presentation/feed_screen.dart';
import '../features/events/presentation/map_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
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

      if (!AppRoutes.isAppPath(location)) {
        return null;
      }

      if (location == AppRoutes.appRoot) {
        if (status == AuthStatus.authenticated) {
          return AppRoutes.feed;
        }
        return AppRoutes.auth;
      }

      final inAuth = location == AppRoutes.auth;

      if (status == AuthStatus.loading) {
        return inAuth ? null : AppRoutes.auth;
      }

      if (status == AuthStatus.unauthenticated) {
        return inAuth ? null : AppRoutes.auth;
      }

      if (status == AuthStatus.authenticated && inAuth) {
        return AppRoutes.feed;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.landing,
        builder: (context, state) => const LandingScreen(),
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
        builder: (context, state) => const AuthScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.feed,
            builder: (context, state) => const FeedScreen(),
          ),
          GoRoute(
            path: AppRoutes.map,
            builder: (context, state) => const MapScreen(),
          ),
          GoRoute(
            path: AppRoutes.create,
            builder: (context, state) => const CreateEventScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.admin,
            builder: (context, state) => const AdminScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/space_app/event/:id',
        builder: (context, state) {
          final eventId = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return EventDetailsScreen(
            eventId: eventId,
            eventKey: state.uri.queryParameters['key'] ??
                state.uri.queryParameters['eventKey'],
          );
        },
      ),
    ],
  );
});
