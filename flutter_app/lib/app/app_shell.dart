import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../ui/theme/app_breakpoints.dart';
import '../ui/theme/app_colors.dart';
import '../ui/theme/app_radii.dart';
import '../ui/theme/app_spacing.dart';
import 'routes.dart';

/// AppShell represents app shell.

class AppShell extends ConsumerStatefulWidget {
  /// AppShell handles app shell.
  const AppShell({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  /// createState creates state.

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// _AppShellState represents app shell state.

class _AppShellState extends ConsumerState<AppShell> {
  static const List<_ShellDestination> _destinations = <_ShellDestination>[
    /// _ShellDestination handles shell destination.
    _ShellDestination(
      label: 'Лента',
      icon: Icons.view_list_rounded,
      branchIndex: 0,
    ),

    /// _ShellDestination handles shell destination.
    _ShellDestination(
      label: 'Карта',
      icon: Icons.map_rounded,
      branchIndex: 1,
    ),

    /// _ShellDestination handles shell destination.
    _ShellDestination(
      label: 'Профиль',
      icon: Icons.person_outline_rounded,
      branchIndex: 3,
    ),
  ];

  /// didChangeDependencies handles did change dependencies.

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

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = widget.navigationShell.currentIndex;
    final isAdminRoute = location.startsWith(AppRoutes.admin);
    final isCreateRoute = location.startsWith(AppRoutes.create);
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= AppBreakpoints.smMax;
    final selectedNavIndex = _selectedDestinationIndex(currentIndex);

    if (!isAdminRoute && !isCreateRoute && isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: _AppNavigationRail(
                selectedIndex: selectedNavIndex,
                destinations: _destinations,
                onSelected: _onDestinationSelected,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: isAdminRoute || isCreateRoute
          ? null
          : _AppBottomDock(
              selectedIndex: selectedNavIndex,
              destinations: _destinations,
              onSelected: _onDestinationSelected,
            ),
    );
  }

  /// _onDestinationSelected handles on destination selected.

  void _onDestinationSelected(int index) {
    if (index < 0 || index >= _destinations.length) return;
    final branchIndex = _destinations[index].branchIndex;
    if (branchIndex == widget.navigationShell.currentIndex) return;
    widget.navigationShell.goBranch(branchIndex);
  }

  /// _selectedDestinationIndex maps shell branch index to visible nav index.

  int _selectedDestinationIndex(int branchIndex) {
    final index = _destinations.indexWhere(
      (destination) => destination.branchIndex == branchIndex,
    );
    return index >= 0 ? index : 0;
  }
}

/// _AppBottomDock represents app bottom dock.

class _AppBottomDock extends StatelessWidget {
  /// _AppBottomDock handles app bottom dock.
  const _AppBottomDock({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelected;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    (isDark
                            ? AppColors.darkSurfaceStrong
                            : AppColors.surfaceStrong)
                        .withValues(alpha: isDark ? 0.92 : 0.96),
                    (isDark ? AppColors.darkSurface : AppColors.surface)
                        .withValues(alpha: isDark ? 0.9 : 0.94),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(
                    alpha: isDark ? 0.8 : 1,
                  ),
                ),
                borderRadius: BorderRadius.circular(AppRadii.xxl),
              ),
              child: NavigationBar(
                height: 68,
                backgroundColor: Colors.transparent,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: selectedIndex,
                destinations: [
                  for (final item in destinations)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
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

/// _AppNavigationRail represents app navigation rail.

class _AppNavigationRail extends StatelessWidget {
  /// _AppNavigationRail handles app navigation rail.
  const _AppNavigationRail({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_ShellDestination> destinations;
  final ValueChanged<int> onSelected;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 96,
      margin: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        color: theme.colorScheme.surface.withValues(
          alpha: isDark ? 0.8 : 0.92,
        ),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: isDark ? 0.8 : 1),
        ),
      ),
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.4,
        minWidth: 88,
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            'SPACE',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        destinations: [
          for (final item in destinations)
            NavigationRailDestination(
              icon: Icon(item.icon),
              label: Text(item.label),
            ),
        ],
      ),
    );
  }
}

/// _ShellDestination represents shell destination.

class _ShellDestination {
  /// _ShellDestination handles shell destination.
  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.branchIndex,
  });

  final String label;
  final IconData icon;
  final int branchIndex;
}
