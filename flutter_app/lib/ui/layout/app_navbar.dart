import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

class AppNavbarItem {
  const AppNavbarItem({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

class AppTopNavbar extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.surface,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
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
    );
  }
}

class _NavChip extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final background = active
        ? AppColors.secondary.withValues(alpha: 0.18)
        : AppColors.surfaceStrong.withValues(alpha: 0.74);
    final border = active
        ? AppColors.secondary.withValues(alpha: 0.5)
        : AppColors.borderStrong.withValues(alpha: 0.8);

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
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
