import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rwanda_food_price_predictor/main.dart';

void main() {
  testWidgets('Page has 8 input fields and a Predict button', (tester) async {
    await tester.pumpWidget(const FoodPriceApp());
    expect(find.byType(TextField), findsNWidgets(8));
    expect(find.text('Predict'), findsOneWidget);
  });

  testWidgets('Shows a readable error when a value is missing', (tester) async {
    await tester.pumpWidget(const FoodPriceApp());
    await tester.ensureVisible(find.text('Predict'));
    await tester.tap(find.text('Predict'));
    await tester.pump();
    expect(find.textContaining('is missing'), findsOneWidget);
  });
}
