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

/// EventCardTile represents event card tile.

class EventCardTile extends StatelessWidget {
  /// EventCardTile handles event card tile.
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

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBestEvent = event.isFeatured;
    final distanceText = _distanceText();
    final semanticLabel = <String>[
      'Открыть событие ${event.title}',
      formatDateTime(event.startsAt),
      if (distanceText != null) distanceText,
    ].join(', ');

    final contentCard = Semantics(
      button: true,
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: AppCard(
        variant: isBestEvent ? AppCardVariant.surface : AppCardVariant.panel,
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CardMedia(
                  event: event,
                  apiUrl: apiUrl,
                  accessKey: accessKey,
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Color(0xE6000000),
                          Color(0x66000000),
                          Color(0x00000000),
                        ],
                        stops: <double>[0, 0.48, 0.78],
                      ),
                    ),
                  ),
                ),
                if (isBestEvent)
                  const Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: AppBadge(
                      label: 'ЛУЧШЕЕ СОБЫТИЕ',
                      variant: AppBadgeVariant.accent,
                    ),
                  ),
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: _LikeButton(
                    isLiked: event.isLiked,
                    onTap: onLikeTap,
                    loading: likeLoading,
                  ),
                ),
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: _EventCardSummary(
                    event: event,
                    distanceText: distanceText,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  /// Returns a localized distance label when a reference point is available.
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

/// Renders the textual and statistical content over the event image.
class _EventCardSummary extends StatelessWidget {
  const _EventCardSummary({
    required this.event,
    required this.distanceText,
  });

  final EventCard event;
  final String? distanceText;

  /// Builds a high-contrast summary that remains readable over arbitrary media.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          event.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            shadows: const <Shadow>[
              Shadow(color: Colors.black87, blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          formatDateTime(event.startsAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.88),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _StatPill(
              icon: Icons.people_alt_outlined,
              label: '${event.participantsCount}',
            ),
            _StatPill(
              icon: Icons.favorite_rounded,
              label: '${event.likesCount}',
            ),
            _StatPill(
              icon: Icons.chat_bubble_outline_rounded,
              label: '${event.commentsCount}',
            ),
            if (distanceText != null)
              _StatPill(
                icon: Icons.near_me_outlined,
                label: distanceText!,
              ),
          ],
        ),
      ],
    );
  }
}

/// Displays a compact statistic without creating an additional tap target.
class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Builds a contrast-safe icon and value badge.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _LikeButton represents icon-only like action.

class _LikeButton extends StatelessWidget {
  /// _LikeButton handles compact like action.
  const _LikeButton({
    required this.isLiked,
    required this.onTap,
    required this.loading,
  });

  final bool isLiked;
  final VoidCallback onTap;
  final bool loading;

  /// build renders the widget tree for this component.

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

    final semanticLabel =
        isLiked ? 'Убрать из избранного' : 'Добавить в избранное';
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        enabled: !loading,
        label: semanticLabel,
        child: Opacity(
          opacity: loading ? 0.76 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              onTap: loading ? null : onTap,
              child: Ink(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: borderColor),
                  boxShadow: shadow,
                ),
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(iconColor),
                          ),
                        )
                      : Icon(
                          isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 20,
                          color: iconColor,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// _CardMedia represents card media.

class _CardMedia extends StatelessWidget {
  /// _CardMedia handles card media.
  const _CardMedia({
    required this.event,
    required this.apiUrl,
    required this.accessKey,
  });

  final EventCard event;
  final String apiUrl;
  final String accessKey;

  /// build renders the widget tree for this component.

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

    return hasThumbnail
        ? Image.network(
            mediaUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) {
              if (fallbackUrl.isNotEmpty && fallbackUrl != mediaUrl) {
                return Image.network(
                  fallbackUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) => const _PlaceholderImage(),
                );
              }
              return const _PlaceholderImage();
            },
          )
        : const _PlaceholderImage();
  }
}

/// _PlaceholderImage represents placeholder image.

class _PlaceholderImage extends StatelessWidget {
  /// _PlaceholderImage handles placeholder image.
  const _PlaceholderImage();

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A2643),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white70,
        size: 32,
      ),
    );
  }
}
