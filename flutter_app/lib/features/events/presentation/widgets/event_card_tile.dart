import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/models/event_card.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../../../core/utils/event_media_url_utils.dart';
import '../../../../ui/components/app_badge.dart';
import '../../../../ui/components/app_card.dart';
import '../../../../ui/theme/app_colors.dart';
import '../../../../ui/theme/app_radii.dart';
import '../../../../ui/theme/app_spacing.dart';

class EventCardTile extends StatelessWidget {
  const EventCardTile({
    required this.event,
    required this.onTap,
    required this.onLikeTap,
    required this.apiUrl,
    this.referencePoint,
    this.accessKey = '',
    this.likeLoading = false,
    super.key,
  });

  final EventCard event;
  final VoidCallback onTap;
  final VoidCallback onLikeTap;
  final String apiUrl;
  final LatLng? referencePoint;
  final String accessKey;
  final bool likeLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBestEvent = event.isFeatured;
    const isMobileUi = !kIsWeb;
    final cardPadding = isMobileUi
        ? (isBestEvent ? AppSpacing.lg : AppSpacing.md)
        : (isBestEvent ? AppSpacing.md : AppSpacing.sm);
    final mediaSize = isMobileUi
        ? (isBestEvent ? 164.0 : 142.0)
        : (isBestEvent ? 128.0 : 110.0);
    final titleStyle = isBestEvent
        ? (isMobileUi
            ? theme.textTheme.headlineSmall
            : theme.textTheme.titleLarge)
        : (isMobileUi
            ? theme.textTheme.titleLarge
            : theme.textTheme.titleMedium);
    final descriptionMaxLines =
        isBestEvent ? (isMobileUi ? 4 : 3) : (isMobileUi ? 3 : 2);
    final startsAt = formatDateTime(event.startsAt);
    final distanceText = _distanceText();
    final titleTextColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final badgeTextStyle = theme.textTheme.labelSmall?.copyWith(
      color: titleTextColor,
    );
    final contentCard = AppCard(
      variant: isBestEvent ? AppCardVariant.surface : AppCardVariant.panel,
      onTap: onTap,
      padding: EdgeInsets.all(cardPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardMedia(
            event: event,
            apiUrl: apiUrl,
            accessKey: accessKey,
            distanceText: distanceText,
            mediaSize: mediaSize,
          ),
          const SizedBox(width: isMobileUi ? AppSpacing.md : AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBestEvent) ...[
                  AppBadge(
                    label: 'ЛУЧШЕЕ СОБЫТИЕ',
                    variant: AppBadgeVariant.accent,
                    textStyle: badgeTextStyle?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  event.title,
                  style: titleStyle?.copyWith(
                    color: titleTextColor,
                    fontWeight: isBestEvent ? FontWeight.w700 : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  startsAt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  event.description,
                  maxLines: descriptionMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _StatBadge(
                      icon: Icons.people_alt_outlined,
                      value: event.participantsCount,
                      textStyle: badgeTextStyle,
                    ),
                    _LikeBadge(
                      likesCount: event.likesCount,
                      isLiked: event.isLiked,
                      onTap: onLikeTap,
                      loading: likeLoading,
                      textStyle: badgeTextStyle,
                    ),
                    _StatBadge(
                      icon: Icons.chat_bubble_outline_rounded,
                      value: event.commentsCount,
                      textStyle: badgeTextStyle,
                    ),
                    if (distanceText != null)
                      _DistanceBadge(
                        distanceText: distanceText,
                        textStyle: badgeTextStyle,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!isBestEvent) return contentCard;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl + 2),
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF214C9A),
                  Color(0xFF123061),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFFFF8D9),
                  Color(0xFFFFEEC2),
                ],
              ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? AppColors.secondary.withValues(alpha: 0.36)
                : AppColors.warning.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: contentCard,
      ),
    );
  }

  String? _distanceText() {
    if (referencePoint == null) return null;
    final km = haversineKm(
      lat1: referencePoint!.latitude,
      lng1: referencePoint!.longitude,
      lat2: event.lat,
      lng2: event.lng,
    );
    return formatDistanceKm(km);
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.value,
    this.textStyle,
  });

  final IconData icon;
  final int value;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final decoration = BoxDecoration(
      color: AppColors.info.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(AppRadii.pill),
      border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
    );

    return DecoratedBox(
      decoration: decoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: textColor,
            ),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: (textStyle ?? theme.textTheme.labelSmall)?.copyWith(
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeBadge extends StatelessWidget {
  const _LikeBadge({
    required this.likesCount,
    required this.isLiked,
    required this.onTap,
    required this.loading,
    this.textStyle,
  });

  final int likesCount;
  final bool isLiked;
  final VoidCallback onTap;
  final bool loading;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final likeAccent = theme.colorScheme.error;
    final textColor = isLiked
        ? (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)
        : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary);
    final iconColor = isLiked ? likeAccent : textColor;
    final backgroundColor = isLiked
        ? likeAccent.withValues(alpha: isDark ? 0.28 : 0.1)
        : AppColors.info.withValues(alpha: 0.16);
    final borderColor = isLiked
        ? likeAccent.withValues(alpha: isDark ? 0.82 : 0.42)
        : AppColors.info.withValues(alpha: 0.4);
    final shadow = isLiked && isDark
        ? <BoxShadow>[
            BoxShadow(
              color: likeAccent.withValues(alpha: 0.34),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ]
        : const <BoxShadow>[];

    return Opacity(
      opacity: loading ? 0.76 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: loading ? null : onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: borderColor),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                    ),
                  )
                else
                  Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 14,
                    color: iconColor,
                  ),
                const SizedBox(width: 4),
                Text(
                  '$likesCount',
                  style: (textStyle ?? Theme.of(context).textTheme.labelSmall)
                      ?.copyWith(color: textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  const _DistanceBadge({
    required this.distanceText,
    this.textStyle,
  });

  final String distanceText;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: isDark ? 0.24 : 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: AppColors.success.withValues(alpha: isDark ? 0.5 : 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_outlined,
              size: 14,
              color: textColor,
            ),
            const SizedBox(width: 4),
            Text(
              distanceText,
              style: (textStyle ?? theme.textTheme.labelSmall)?.copyWith(
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardMedia extends StatelessWidget {
  const _CardMedia({
    required this.event,
    required this.apiUrl,
    required this.accessKey,
    required this.distanceText,
    required this.mediaSize,
  });

  final EventCard event;
  final String apiUrl;
  final String accessKey;
  final String? distanceText;
  final double mediaSize;

  @override
  Widget build(BuildContext context) {
    final fallbackThumbnail = event.thumbnailUrl.trim();
    final proxyThumbnail = buildEventMediaProxyUrl(
      apiUrl: apiUrl,
      eventId: event.id,
      index: 0,
      accessKey: accessKey,
    );
    final mediaUrl =
        proxyThumbnail.isNotEmpty ? proxyThumbnail : fallbackThumbnail;
    final fallbackUrl = proxyThumbnail.isNotEmpty ? fallbackThumbnail : '';
    final hasThumbnail = mediaUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: SizedBox(
        width: mediaSize,
        height: mediaSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasThumbnail)
              Image.network(
                mediaUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) {
                  if (fallbackUrl.isNotEmpty && fallbackUrl != mediaUrl) {
                    return Image.network(
                      fallbackUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) =>
                          const _PlaceholderImage(),
                    );
                  }
                  return const _PlaceholderImage();
                },
              )
            else
              const _PlaceholderImage(),
            if (distanceText != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    distanceText!,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A2643),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white70,
      ),
    );
  }
}
