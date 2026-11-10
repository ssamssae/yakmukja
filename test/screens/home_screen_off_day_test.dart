import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 오늘 먹는 요일이 아닌 약도 홈에서 보이고 고칠 수 있어야 한다.
/// (T-261110-021 — 요일 약을 다른 날 등록하면 「아직 등록된 약이 없어요」가 나오던 문제)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

  // 2026-11-10 은 화요일(ISO 2).
  DateTime tuesday() => DateTime(2026, 11, 10, 10, 0);

  setUpAll(() async {
    Hive.init(Directory.systemTemp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  setUp(() async {
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
  });

  Medicine med(String name, {List<int>? weekdays, List<DoseTime>? times}) =>
      Medicine(
        name: name,
        dosage: '1알',
        times: times ?? [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: DateTime(2026, 11, 1),
        weekdays: weekdays,
      );

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: tuesday),
      ),
    );
    await tester.pump();
  }

  testWidgets('오늘 먹는 요일이 아닌 약만 있으면 등록 안내 대신 쉬는 날 안내와 그 약이 보인다', (tester) async {
    await box.add(med('골다공증약', weekdays: [3]));
    await pumpHome(tester);

    expect(find.text('아직 등록된 약이 없어요'), findsNothing);
    expect(find.byKey(const Key('home-empty')), findsNothing);
    expect(find.text('오늘은 먹을 약이 없어요'), findsOneWidget);
    expect(find.text('오늘 쉬는 약'), findsOneWidget);
    expect(find.text('골다공증약'), findsOneWidget);
    expect(find.text('수 · 아침 8:00'), findsOneWidget);
  });

  testWidgets('오늘 먹는 약이 있으면 그 아래에 쉬는 약 목록이 따로 나온다', (tester) async {
    await box.add(med('혈압약'));
    await box.add(
      med(
        '주사',
        weekdays: [1, 3, 5],
        times: [DoseTime(hour: 8, minute: 0), DoseTime(hour: 21, minute: 0)],
      ),
    );
    await pumpHome(tester);

    expect(find.text('오늘 0/1 먹었어요'), findsOneWidget);
    expect(find.text('오늘 쉬는 약'), findsOneWidget);
    expect(find.text('주사'), findsOneWidget);
    expect(find.text('월·수·금 · 아침 8:00, 저녁 9:00'), findsOneWidget);
  });

  testWidgets('쉬는 약을 누르면 그 약의 수정 화면이 열린다', (tester) async {
    await box.add(med('골다공증약', weekdays: [3]));
    await pumpHome(tester);

    await tester.tap(find.text('골다공증약'));
    await tester.pumpAndSettle();

    expect(find.text('약 수정'), findsOneWidget);
  });

  testWidgets('매일 먹는 약만 있으면 쉬는 약 목록은 나오지 않는다', (tester) async {
    await box.add(med('혈압약'));
    await pumpHome(tester);

    expect(find.text('오늘 0/1 먹었어요'), findsOneWidget);
    expect(find.text('오늘 쉬는 약'), findsNothing);
  });

  testWidgets('휴지통에 있는 약은 쉬는 약 목록에 나오지 않는다', (tester) async {
    await box.add(med('버린약', weekdays: [3])..deletedAt = DateTime(2026, 11, 9));
    await pumpHome(tester);

    expect(find.text('버린약'), findsNothing);
    expect(find.text('오늘 쉬는 약'), findsNothing);
    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
  });
}
