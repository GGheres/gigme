import 'package:flutter/material.dart';

import 'app_button.dart';

/// PrimaryButton represents primary button.

class PrimaryButton extends StatelessWidget {
  /// PrimaryButton handles primary button.
  const PrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.tooltip,
    this.size = AppButtonSize.md,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;
  final bool expand;
  final String? tooltip;
  final AppButtonSize size;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      loading: loading,
      expand: expand,
      tooltip: tooltip,
      size: size,
      variant: AppButtonVariant.primary,
    );
  }
}

/// SecondaryButton represents secondary button.

class SecondaryButton extends StatelessWidget {
  /// SecondaryButton handles secondary button.
  const SecondaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.tooltip,
    this.size = AppButtonSize.md,
    this.outline = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;
  final bool expand;
  final String? tooltip;
  final AppButtonSize size;
  final bool outline;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      loading: loading,
      expand: expand,
      tooltip: tooltip,
      size: size,
      variant: outline ? AppButtonVariant.outline : AppButtonVariant.secondary,
    );
  }
}

/// AppIconButton represents app icon button.

class AppIconButton extends StatelessWidget {
  /// AppIconButton handles app icon button.
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.variant = AppButtonVariant.ghost,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = variant == AppButtonVariant.secondary
        ? theme.colorScheme.primary.withValues(alpha: 0.16)
        : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: background,
          foregroundColor: theme.colorScheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
