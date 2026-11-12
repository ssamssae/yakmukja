import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';
import 'package:yakmukja/widgets/pill_glyph.dart';

void main() {
  testWidgets('new registration has no pill picture and a save button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MedicineEditScreen()),
    );

    expect(find.text('약 등록'), findsOneWidget);
    expect(find.byType(PillGlyph), findsNothing);
    expect(find.text('저장'), findsOneWidget);
    expect(find.byTooltip('취소'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pump();

    expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('existing medicine keeps dosage, times, and delete', (
    tester,
  ) async {
    final medicine = Medicine(
      name: '오메가3',
      dosage: '2알',
      times: [DoseTime(hour: 8, minute: 30)],
      memo: '',
      createdAt: DateTime(2026, 11, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicineEditScreen(medicine: medicine),
      ),
    );

    expect(find.text('약 수정'), findsOneWidget);
    expect(find.text('오메가3'), findsOneWidget);
    expect(find.text('2알'), findsOneWidget);
    expect(find.text('아침 8:30'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
    expect(find.byType(PillGlyph), findsNothing);
  });

  testWidgets('section add buttons sit at the right edge of the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MedicineEditScreen()),
    );

    // 제목 줄의 「+ 추가」는 카드 오른쪽 끝에 붙는다. 제목 바로 옆에 붙지 않는다.
    final screenWidth = tester.getSize(find.byType(MedicineEditScreen)).width;
    final adds = find.text('추가');
    expect(adds, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(screenWidth - tester.getRect(adds.at(i)).right, lessThan(60));
    }
  });
}
