import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';
import '../theme/app_tokens.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  danger,
}

enum AppButtonSize {
  sm,
  md,
  lg,
}

class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.expand = false,
    this.tooltip,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool expand;
  final String? tooltip;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final visual = _resolveVisual(
      widget.variant,
      enabled: _enabled,
      isDark: isDark,
    );
    final metrics = _resolveMetrics(widget.size, theme);
    final shadows = <BoxShadow>[
      ...visual.shadows,
      if (_hovered && _enabled) ...AppShadows.buttonHover,
      if (_focused)
        const BoxShadow(
            color: AppColors.focusRing, blurRadius: 0, spreadRadius: 2),
    ];

    Widget button = AnimatedContainer(
      duration: AppDurations.normal,
      curve: AppMotionCurves.standard,
      width: widget.expand ? double.infinity : null,
      decoration: BoxDecoration(
        gradient: visual.gradient,
        color: visual.gradient == null ? visual.background : null,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: visual.borderColor),
        boxShadow: shadows,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: _enabled ? widget.onPressed : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: metrics.height),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.horizontalPadding,
                vertical: metrics.verticalPadding,
              ),
              child: IconTheme(
                data: IconThemeData(
                    size: metrics.iconSize, color: visual.foreground),
                child: DefaultTextStyle(
                  style: metrics.textStyle.copyWith(color: visual.foreground),
                  child: Row(
                    mainAxisSize:
                        widget.expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.loading)
                        SizedBox(
                          width: metrics.iconSize,
                          height: metrics.iconSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                visual.foreground),
                          ),
                        )
                      else if (widget.icon != null)
                        widget.icon!,
                      if (widget.loading || widget.icon != null)
                        const SizedBox(width: 8),
                      Flexible(
                          child: Text(widget.label,
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.trim().isNotEmpty) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return Opacity(
      opacity: _enabled ? 1 : 0.56,
      child: Focus(
        onFocusChange: (value) {
          if (_focused == value) return;
          setState(() => _focused = value);
        },
        child: MouseRegion(
          cursor:
              _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: button,
        ),
      ),
    );
  }
}

class _ButtonMetrics {
  const _ButtonMetrics({
    required this.height,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.iconSize,
    required this.textStyle,
  });

  final double height;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconSize;
  final TextStyle textStyle;
}

class _ButtonVisual {
  const _ButtonVisual({
    this.gradient,
    required this.background,
    required this.borderColor,
    required this.foreground,
    required this.shadows,
  });

  final Gradient? gradient;
  final Color background;
  final Color borderColor;
  final Color foreground;
  final List<BoxShadow> shadows;
}

_ButtonMetrics _resolveMetrics(AppButtonSize size, ThemeData theme) {
  switch (size) {
    case AppButtonSize.sm:
      return _ButtonMetrics(
        height: 36,
        horizontalPadding: 14,
        verticalPadding: 8,
        iconSize: 16,
        textStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 12),
      );
    case AppButtonSize.md:
      return _ButtonMetrics(
        height: 44,
        horizontalPadding: 18,
        verticalPadding: 10,
        iconSize: 18,
        textStyle: theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14),
      );
    case AppButtonSize.lg:
      return _ButtonMetrics(
        height: 50,
        horizontalPadding: 22,
        verticalPadding: 12,
        iconSize: 20,
        textStyle: theme.textTheme.titleSmall ?? const TextStyle(fontSize: 16),
      );
  }
}

_ButtonVisual _resolveVisual(AppButtonVariant variant,
    {required bool enabled, required bool isDark}) {
  switch (variant) {
    case AppButtonVariant.primary:
      return _ButtonVisual(
        gradient: AppColors.primaryButtonGradient,
        background: AppColors.primary,
        borderColor: Colors.transparent,
        foreground: AppColors.textInverse,
        shadows: enabled ? AppShadows.button : const <BoxShadow>[],
      );
    case AppButtonVariant.secondary:
      return _ButtonVisual(
        gradient: AppColors.secondaryButtonGradient,
        background: AppColors.secondary,
        borderColor: Colors.transparent,
        foreground: isDark ? AppColors.backgroundDeep : AppColors.textPrimary,
        shadows: enabled ? AppShadows.button : const <BoxShadow>[],
      );
    case AppButtonVariant.outline:
      return _ButtonVisual(
        background: isDark
            ? AppColors.darkSurfaceStrong.withValues(alpha: 0.7)
            : AppColors.surfaceStrong,
        borderColor:
            isDark ? AppColors.darkBorderStrong : AppColors.borderStrong,
        foreground: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
        shadows: <BoxShadow>[],
      );
    case AppButtonVariant.ghost:
      return _ButtonVisual(
        background: (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)
            .withValues(alpha: 0.08),
        borderColor:
            (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)
                .withValues(alpha: 0.16),
        foreground: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
        shadows: const <BoxShadow>[],
      );
    case AppButtonVariant.danger:
      return _ButtonVisual(
        gradient: AppColors.dangerButtonGradient,
        background: AppColors.danger,
        borderColor: Colors.transparent,
        foreground: AppColors.textInverse,
        shadows: enabled ? AppShadows.button : const <BoxShadow>[],
      );
  }
}
