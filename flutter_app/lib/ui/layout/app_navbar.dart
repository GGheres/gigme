import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// AppNavbarItem represents app navbar item.

class AppNavbarItem {
  /// AppNavbarItem handles app navbar item.
  const AppNavbarItem({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

/// AppTopNavbar represents app top navbar.

class AppTopNavbar extends StatelessWidget {
  /// AppTopNavbar handles app top navbar.
  const AppTopNavbar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.title = 'SPACE',
    super.key,
  });

  final List<AppNavbarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String title;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xxl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xB3111E3E),
                Color(0xB30C1630),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadii.xxl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const <BoxShadow>[
              ...AppShadows.surface,
              BoxShadow(
                color: Color(0x47121A33),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.secondaryButtonGradient,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _NavChip(
                      label: items[i].label,
                      icon: items[i].icon,
                      active: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// _NavChip represents nav chip.

class _NavChip extends StatelessWidget {
  /// _NavChip handles nav chip.
  const _NavChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final background = active ? null : Colors.white.withValues(alpha: 0.06);
    final border = active
        ? Colors.white.withValues(alpha: 0.26)
        : Colors.white.withValues(alpha: 0.12);
    final textColor =
        active ? Colors.white : Colors.white.withValues(alpha: 0.9);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            color: background,
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color(0xFF3B7BFF),
                      Color(0xFF6A4CFF),
                    ],
                  )
                : null,
            border: Border.all(color: border),
            boxShadow: active
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x4D3B7BFF),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
