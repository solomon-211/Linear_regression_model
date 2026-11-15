import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uganda_learning_predictor/main.dart';

void main() {
  testWidgets('Page has 12 input fields and a Predict button', (tester) async {
    await tester.pumpWidget(const LearningPredictorApp());
    expect(find.byType(TextField), findsNWidgets(12));
    expect(find.text('Predict'), findsOneWidget);
  });

  testWidgets('Shows a readable error when a value is missing', (tester) async {
    await tester.pumpWidget(const LearningPredictorApp());
    await tester.ensureVisible(find.text('Predict'));
    await tester.tap(find.text('Predict'));
    await tester.pump();
    expect(find.textContaining('is missing'), findsOneWidget);
  });
}
