import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 복용량은 선택 사항이고, 알 말고 다른 단위(포·ml 등)도 고를 수 있다.
/// (T-261110-029)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

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

  Future<Medicine> addMedicine(String dosage) async {
    await box.add(
      Medicine(
        name: '혈압약',
        dosage: dosage,
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    return box.values.single;
  }

  Future<void> pumpEdit(WidgetTester tester, {Medicine? medicine}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicineEditScreen(medicine: medicine),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 복용량 선택 창의 휠을 [value] 칸으로 돌린다.
  Future<void> spin(
    WidgetTester tester,
    String pickerKey,
    List<String> options,
    String value,
  ) async {
    final picker = tester.widget<CupertinoPicker>(find.byKey(Key(pickerKey)));
    picker.scrollController!.jumpToItem(options.indexOf(value));
    await tester.pump();
  }

  testWidgets('복용량을 지우고 저장해도 저장된다 — 복용량은 선택 사항이다', (tester) async {
    final medicine = await addMedicine('1알');
    await pumpEdit(tester, medicine: medicine);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Chip, '1알'),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('복용량을 추가해 주세요.'), findsNothing);
    expect(medicine.dosage, '');
  });

  testWidgets('복용량 칸 제목 옆에 선택 사항 표시가 있다', (tester) async {
    await pumpEdit(tester);

    expect(find.text('(선택)'), findsOneWidget);
  });

  testWidgets('단위 휠에서 「포」를 고르면 「1포」가 된다', (tester) async {
    await pumpEdit(tester);
    await tester.tap(find.text('복용량 추가하기'));
    await tester.pumpAndSettle();

    await spin(
      tester,
      'dosage-unit-picker',
      MedicineEditScreen.dosageUnits,
      '포',
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, '1포'), findsOneWidget);
  });

  testWidgets('물약처럼 양이 큰 것도 고를 수 있다 — 「15ml」', (tester) async {
    await pumpEdit(tester);
    await tester.tap(find.text('복용량 추가하기'));
    await tester.pumpAndSettle();

    await spin(
      tester,
      'dosage-amount-picker',
      MedicineEditScreen.dosageAmounts,
      '15',
    );
    await spin(
      tester,
      'dosage-unit-picker',
      MedicineEditScreen.dosageUnits,
      'ml',
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, '15ml'), findsOneWidget);
  });

  testWidgets('저장된 「5ml」를 열어 그대로 확인하면 「5ml」가 유지된다', (tester) async {
    final medicine = await addMedicine('5ml');
    await pumpEdit(tester, medicine: medicine);

    // 복용량 칸의 「+ 추가」(첫 번째)가 선택 창을 연다.
    await tester.tap(find.text('추가').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, '5ml'), findsOneWidget);
  });

  testWidgets('종전 기본값은 그대로다 — 아무것도 돌리지 않고 확인하면 「1알」', (tester) async {
    await pumpEdit(tester);
    await tester.tap(find.text('복용량 추가하기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, '1알'), findsOneWidget);
  });

  test('단위 목록은 알부터 시작하고, 양은 종전 0.5~10 에 큰 양이 더해진다', () {
    expect(MedicineEditScreen.dosageUnits.first, '알');
    expect(
      MedicineEditScreen.dosageUnits,
      containsAll(['알', '캡슐', '포', 'ml', '방울']),
    );
    expect(MedicineEditScreen.dosageAmounts.take(3), ['0.5', '1', '1.5']);
    expect(MedicineEditScreen.dosageAmounts, containsAll(['10', '15', '20']));
  });
}
