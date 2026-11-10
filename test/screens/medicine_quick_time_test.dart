import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 자주 쓰는 복용 시간(아침·점심·저녁·자기 전)은 휠을 돌리지 않고 한 번 눌러 넣는다.
/// (T-261110-032)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

  Finder quick(int hour, int minute) =>
      find.byKey(Key('quick-time-$hour-$minute'));

  setUpAll(() async {
    Hive.init(Directory.systemTemp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  setUp(() async {
    NotificationService.resetForTest();
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
  });

  Future<void> pumpEdit(WidgetTester tester, {Medicine? medicine}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicineEditScreen(medicine: medicine),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapQuick(WidgetTester tester, int hour, int minute) async {
    await tester.ensureVisible(quick(hour, minute));
    await tester.tap(quick(hour, minute));
    await tester.pumpAndSettle();
  }

  testWidgets('빠른 추가 단추 네 개가 이름과 시각을 보여 준다', (tester) async {
    await pumpEdit(tester);

    expect(
      find.descendant(of: quick(8, 0), matching: find.text('아침 8:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quick(12, 30), matching: find.text('점심 12:30')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quick(19, 0), matching: find.text('저녁 7:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quick(22, 0), matching: find.text('자기 전 10:00')),
      findsOneWidget,
    );
  });

  testWidgets('「아침 8:00」을 누르면 선택 창 없이 바로 그 시간이 들어간다', (tester) async {
    await pumpEdit(tester);

    await tapQuick(tester, 8, 0);

    expect(find.widgetWithText(Chip, '아침 8:00'), findsOneWidget);
    // 시간 선택 창(취소 단추가 있다)은 열리지 않았다.
    expect(find.text('취소'), findsNothing);
    // 이미 넣은 시간의 단추는 사라진다.
    expect(quick(8, 0), findsNothing);
    expect(quick(19, 0), findsOneWidget);
  });

  testWidgets('이미 있는 시간의 빠른 추가 단추는 처음부터 나오지 않는다', (tester) async {
    await box.add(
      Medicine(
        name: '혈압약',
        dosage: '1알',
        times: [DoseTime(hour: 19, minute: 0)],
        memo: '',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    await pumpEdit(tester, medicine: box.values.single);

    expect(quick(19, 0), findsNothing);
    expect(quick(8, 0), findsOneWidget);
  });

  testWidgets('네 개를 모두 넣으면 빠른 추가 줄이 사라진다', (tester) async {
    await pumpEdit(tester);

    await tapQuick(tester, 8, 0);
    await tapQuick(tester, 12, 30);
    await tapQuick(tester, 19, 0);
    await tapQuick(tester, 22, 0);

    expect(find.byKey(const Key('quick-time-row')), findsNothing);
  });

  testWidgets('빠른 추가로 넣은 시간은 시간순으로 저장된다', (tester) async {
    await pumpEdit(tester);
    await tester.enterText(find.byType(TextFormField), '혈압약');

    await tapQuick(tester, 19, 0);
    await tapQuick(tester, 8, 0);
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(box.values.single.times.map((t) => t.format()).toList(), [
      '아침 8:00',
      '저녁 7:00',
    ]);
  });
}
