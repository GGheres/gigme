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
    required this.apiUrl,
    this.referencePoint,
    this.accessKey = '',
    super.key,
  });

  final EventCard event;
  final VoidCallback onTap;
  final String apiUrl;
  final LatLng? referencePoint;
  final String accessKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const isMobileUi = !kIsWeb;
    const cardPadding = isMobileUi ? AppSpacing.md : AppSpacing.sm;
    const mediaSize = isMobileUi ? 142.0 : 110.0;
    final titleStyle =
        isMobileUi ? theme.textTheme.titleLarge : theme.textTheme.titleMedium;
    const descriptionMaxLines = isMobileUi ? 3 : 2;
    final startsAt = formatDateTime(event.startsAt);
    final distanceText = _distanceText();

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(cardPadding),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: titleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (event.isFeatured) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const AppBadge(
                        label: 'Featured',
                        variant: AppBadgeVariant.accent,
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  startsAt,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  event.description,
                  maxLines: descriptionMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    AppBadge(
                      label: '${event.participantsCount} going',
                      variant: AppBadgeVariant.ghost,
                    ),
                    AppBadge(
                      label: '${event.likesCount} likes',
                      variant: AppBadgeVariant.ghost,
                    ),
                    AppBadge(
                      label: '${event.commentsCount} comments',
                      variant: AppBadgeVariant.ghost,
                    ),
                    if (distanceText != null)
                      AppBadge(
                        label: distanceText,
                        variant: AppBadgeVariant.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}
