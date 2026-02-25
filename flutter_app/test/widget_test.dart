import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

/// main is the application entry point.

void main() {
  testWidgets('Widget test harness is operational',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );

    expect(find.byType(SizedBox), findsOneWidget);
  });
}
