import 'package:flutter/material.dart';

import '../../../../core/models/user.dart';
import '../../../../ui/components/app_badge.dart';
import '../../../../ui/components/app_card.dart';
import '../../../../ui/theme/app_spacing.dart';

class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    required this.user,
    super.key,
  });

  final User? user;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user?.displayName ?? 'Unknown user',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xxs),
          if ((user?.handle ?? '').isNotEmpty) Text(user!.handle),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppBadge(
                label: 'Rating ${user?.rating.toStringAsFixed(1) ?? '0.0'}',
                variant: AppBadgeVariant.ghost,
              ),
              AppBadge(
                label: 'Votes ${user?.ratingCount ?? 0}',
                variant: AppBadgeVariant.ghost,
              ),
              AppBadge(
                label: '${user?.balanceTokens ?? 0} GT',
                variant: AppBadgeVariant.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
