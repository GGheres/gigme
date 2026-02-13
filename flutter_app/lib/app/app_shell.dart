import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../ui/layout/app_navbar.dart';
import '../ui/theme/app_breakpoints.dart';
import '../ui/theme/app_radii.dart';
import '../ui/theme/app_spacing.dart';
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
  static const List<AppNavbarItem> _desktopItems = <AppNavbarItem>[
    AppNavbarItem(label: 'Feed', icon: Icons.view_list_rounded),
    AppNavbarItem(label: 'Map', icon: Icons.map_rounded),
    AppNavbarItem(label: 'Create', icon: Icons.add_circle_outline_rounded),
    AppNavbarItem(label: 'Profile', icon: Icons.person_outline_rounded),
  ];

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
      context.go(uri.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromLocation(location);
    final isAdminRoute = location.startsWith(AppRoutes.admin);
    final isDesktop = MediaQuery.sizeOf(context).width >= AppBreakpoints.smMax;

    return Scaffold(
      body: Column(
        children: [
          if (!isAdminRoute && isDesktop)
            SafeArea(
              bottom: false,
              child: AppTopNavbar(
                items: _desktopItems,
                selectedIndex: currentIndex,
                onSelected: _onDestinationSelected,
              ),
            ),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: isAdminRoute
          ? null
          : isDesktop
              ? null
              : _AppBottomDock(
                  selectedIndex: currentIndex,
                  onSelected: _onDestinationSelected,
                ),
    );
  }

  void _onDestinationSelected(int index) {
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
  }

  int _indexFromLocation(String location) {
    if (location.startsWith(AppRoutes.map)) return 1;
    if (location.startsWith(AppRoutes.create)) return 2;
    if (location.startsWith(AppRoutes.profile)) return 3;
    return 0;
  }
}

class _AppBottomDock extends StatelessWidget {
  const _AppBottomDock({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xxl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xCC101D3D),
                    Color(0xCC0B1630),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                borderRadius: BorderRadius.circular(AppRadii.xxl),
              ),
              child: NavigationBar(
                height: 66,
                backgroundColor: Colors.transparent,
                selectedIndex: selectedIndex,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.view_list_rounded),
                    label: 'Feed',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_rounded),
                    label: 'Map',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.add_circle_outline_rounded),
                    label: 'Create',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    label: 'Profile',
                  ),
                ],
                onDestinationSelected: onSelected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
