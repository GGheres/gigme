import 'package:flutter/material.dart';

import '../../../../core/models/user.dart';

class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    required this.user,
    required this.loading,
    required this.onTopup,
    super.key,
  });

  final User? user;
  final bool loading;
  final VoidCallback onTopup;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.displayName ?? 'Unknown user',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            if ((user?.handle ?? '').isNotEmpty) Text(user!.handle),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Rating ${user?.rating.toStringAsFixed(1) ?? '0.0'}')),
                Chip(label: Text('Votes ${user?.ratingCount ?? 0}')),
                Chip(label: Text('${user?.balanceTokens ?? 0} GT')),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: loading ? null : onTopup,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Topup tokens'),
            ),
          ],
        ),
      ),
    );
  }
}
