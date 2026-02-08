import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/core/models/user.dart';
import 'package:gigme_flutter/features/profile/presentation/widgets/profile_summary_card.dart';

void main() {
  testWidgets('renders user and balance chips', (tester) async {
    final user = User(
      id: 1,
      telegramId: 100,
      firstName: 'Jane',
      lastName: 'Doe',
      username: 'jane',
      photoUrl: '',
      rating: 4.7,
      ratingCount: 8,
      balanceTokens: 777,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSummaryCard(
            user: user,
            loading: false,
            onTopup: () {},
          ),
        ),
      ),
    );

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.textContaining('777 GT'), findsOneWidget);
    expect(find.text('Topup tokens'), findsOneWidget);
  });
}
