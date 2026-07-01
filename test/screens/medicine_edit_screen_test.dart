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

  testWidgets('weekday chips expose selected button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const MedicineEditScreen()),
      );

      final monday = find.bySemanticsLabel('월요일 선택');

      expect(
        tester.getSemantics(monday),
        matchesSemantics(
          label: '월요일 선택',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('add buttons expose section-specific semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const MedicineEditScreen()),
      );

      expect(find.bySemanticsLabel('복용량 추가'), findsOneWidget);
      expect(find.bySemanticsLabel('복용 시간 추가'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
