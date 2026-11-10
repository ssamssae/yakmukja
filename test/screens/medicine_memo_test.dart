import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 약에 짧은 메모(예: 식후 30분)를 적고, 먹을 차례가 되면 홈에서 본다.
/// (T-261110-031)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;
  const memoField = Key('medicine-memo-field');
  const homeMemo = Key('home-next-memo');

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

  Future<Medicine> addMedicine({String memo = ''}) async {
    await box.add(
      Medicine(
        name: '혈압약',
        dosage: '1알',
        times: [DoseTime(hour: 21, minute: 30)],
        memo: memo,
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    return box.values.single;
  }

  Future<void> pumpEdit(WidgetTester tester, Medicine medicine) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicineEditScreen(medicine: medicine),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        // 저녁 9:30 약이 「다음 약」이 되는 시각.
        home: HomeScreen(clock: () => DateTime(2026, 11, 10, 21, 0)),
      ),
    );
    await tester.pump();
  }

  testWidgets('메모를 적고 저장하면 약에 메모가 남는다', (tester) async {
    final medicine = await addMedicine();
    await pumpEdit(tester, medicine);

    await tester.ensureVisible(find.byKey(memoField));
    await tester.enterText(find.byKey(memoField), '식후 30분');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.memo, '식후 30분');
  });

  testWidgets('메모 앞뒤 빈칸은 빼고 저장한다', (tester) async {
    final medicine = await addMedicine();
    await pumpEdit(tester, medicine);

    await tester.ensureVisible(find.byKey(memoField));
    await tester.enterText(find.byKey(memoField), '  물과 함께  ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.memo, '물과 함께');
  });

  testWidgets('저장된 메모는 수정 화면에 채워져 있다', (tester) async {
    final medicine = await addMedicine(memo: '식후 30분');
    await pumpEdit(tester, medicine);

    expect(
      tester.widget<TextField>(find.byKey(memoField)).controller!.text,
      '식후 30분',
    );
  });

  testWidgets('메모를 지우고 저장하면 메모가 없어진다', (tester) async {
    final medicine = await addMedicine(memo: '식후 30분');
    await pumpEdit(tester, medicine);

    await tester.ensureVisible(find.byKey(memoField));
    await tester.enterText(find.byKey(memoField), '');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.memo, '');
  });

  testWidgets('홈 「다음 약」 카드에 그 약의 메모가 보인다', (tester) async {
    await addMedicine(memo: '식후 30분');
    await pumpHome(tester);

    expect(
      find.descendant(of: find.byKey(homeMemo), matching: find.text('식후 30분')),
      findsOneWidget,
    );
  });

  testWidgets('메모가 없는 약은 홈에 메모 줄이 없다', (tester) async {
    await addMedicine();
    await pumpHome(tester);

    expect(find.byKey(homeMemo), findsNothing);
  });
}
