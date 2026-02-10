import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import 'routes.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final startup = ref.read(authControllerProvider).consumeStartupLink();
      if (startup == null || startup.eventId == null) return;

      final uri = Uri(
        path: AppRoutes.event(startup.eventId!),
        queryParameters: {
          if ((startup.eventKey ?? '').isNotEmpty) 'key': startup.eventKey!,
          if ((startup.refCode ?? '').isNotEmpty) 'ref': startup.refCode!,
        },
      );
      context.push(uri.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromLocation(location);
    final isAdminRoute = location.startsWith(AppRoutes.admin);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: isAdminRoute
          ? null
          : NavigationBar(
              selectedIndex: currentIndex,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.view_list_rounded), label: 'Feed'),
                NavigationDestination(
                    icon: Icon(Icons.map_rounded), label: 'Map'),
                NavigationDestination(
                    icon: Icon(Icons.add_circle_outline_rounded),
                    label: 'Create'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
              ],
              onDestinationSelected: (index) {
                switch (index) {
                  case 0:
                    context.go(AppRoutes.feed);
                    return;
                  case 1:
                    context.go(AppRoutes.map);
                    return;
                  case 2:
                    context.go(AppRoutes.create);
                    return;
                  case 3:
                    context.go(AppRoutes.profile);
                    return;
                }
              },
            ),
    );
  }

  int _indexFromLocation(String location) {
    if (location.startsWith(AppRoutes.map)) return 1;
    if (location.startsWith(AppRoutes.create)) return 2;
    if (location.startsWith(AppRoutes.profile)) return 3;
    return 0;
  }
}
