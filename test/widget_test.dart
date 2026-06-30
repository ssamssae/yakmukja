import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';

void main() {
  Widget buildSubject() {
    return MaterialApp(theme: AppTheme.light, home: const MedicineEditScreen());
  }

  testWidgets('medicine registration form starts with expected empty state', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('약 등록'), findsOneWidget);
    expect(find.text('복용량 추가하기'), findsOneWidget);
    expect(find.text('복용 시간 추가하기'), findsOneWidget);
    expect(find.text('매일 알림을 받아요'), findsOneWidget);

    for (final weekday in ['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.text(weekday), findsOneWidget);
    }
  });

  testWidgets('save validates medicine name before persistence side effects', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('저장'));
    await tester.pump();

    expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
  });
}
