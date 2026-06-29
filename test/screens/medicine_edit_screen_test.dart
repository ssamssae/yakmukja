import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';

void main() {
  testWidgets('empty dosage and time placeholders are clear add actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MedicineEditScreen()),
    );

    expect(find.text('복용량 추가하기'), findsOneWidget);
    expect(find.text('복용 시간 추가하기'), findsOneWidget);

    await tester.tap(find.text('복용량 추가하기'));
    await tester.pumpAndSettle();

    expect(find.text('복용량 선택'), findsOneWidget);
  });
}
