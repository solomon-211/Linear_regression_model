import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_grade_predictor/main.dart';

void main() {
  testWidgets('Shows 13 input fields and a Predict button', (tester) async {
    await tester.pumpWidget(const GradePredictorApp());

    expect(find.byType(TextField), findsNWidgets(13));
    expect(find.widgetWithText(FilledButton, 'Predict'), findsOneWidget);
  });

  testWidgets('Shows an error when a value is missing', (tester) async {
    await tester.pumpWidget(const GradePredictorApp());

    await tester.ensureVisible(find.text('Predict'));
    await tester.tap(find.text('Predict'));
    await tester.pump();

    expect(find.textContaining('is missing'), findsOneWidget);
  });
}
