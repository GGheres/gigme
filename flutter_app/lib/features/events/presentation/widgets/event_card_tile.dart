import 'package:flutter/material.dart';

import '../../../../core/models/event_card.dart';
import '../../../../core/utils/event_media_url_utils.dart';
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
    this.accessKey = '',
    this.likeLoading = false,
    super.key,
  });

  final EventCard event;
  final VoidCallback onTap;
  final VoidCallback onLikeTap;
  final String apiUrl;
  final String accessKey;
  final bool likeLoading;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBestEvent = event.isFeatured;

    final contentCard = AppCard(
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
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.black.withValues(alpha: isDark ? 0.24 : 0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: _LikeButton(
                  isLiked: event.isLiked,
                  onTap: onLikeTap,
                  loading: likeLoading,
                ),
              ),
            ],
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

    return Opacity(
      opacity: loading ? 0.76 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: loading ? null : onTap,
          child: Ink(
            width: 36,
            height: 36,
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
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  : Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 16,
                      color: iconColor,
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
