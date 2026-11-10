import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 시간이 지났는데 안 먹은 약은 「지금」이 아니라 얼마나 지났는지로 알린다.
/// (T-261110-033)
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

  // 복용 체크는 실제 오늘 날짜에 남는다. 시각만 정한다.
  DateTime todayAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  Future<Medicine> add(String name, int hour, int minute) async {
    final medicine = Medicine(
      name: name,
      dosage: '1알',
      times: [DoseTime(hour: hour, minute: minute)],
      memo: '',
      createdAt: DateTime(2026, 11, 1),
    );
    await box.add(medicine);
    return medicine;
  }

  Future<void> pumpHome(WidgetTester tester, DateTime now) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: () => now),
      ),
    );
    await tester.pump();
  }

  test('30분 넘게 지나면 「지금」 대신 지난 시간을 말한다', () {
    expect(doseRemainText(8 * 60, 8 * 60), '지금');
    expect(doseRemainText(8 * 60, 8 * 60 + 29), '지금');
    expect(doseRemainText(8 * 60, 8 * 60 + 30), '30분 지남');
    expect(doseRemainText(8 * 60, 9 * 60), '1시간 지남');
    expect(doseRemainText(8 * 60, 10 * 60 + 20), '2시간 20분 지남');
    // 아직 안 된 시각은 종전 그대로.
    expect(doseRemainText(8 * 60 + 30, 8 * 60 + 10), '20분 남음');
  });

  testWidgets('큰 카드: 2시간 지난 약은 「지난 약 · 2시간 지남」으로 나온다', (tester) async {
    await add('혈압약', 8, 0);
    await pumpHome(tester, todayAt(10, 0));

    expect(find.text('2시간 지남'), findsOneWidget);
    expect(find.text('지난 약'), findsOneWidget);
    expect(find.text('다음 약'), findsNothing);
    expect(find.text('지금'), findsNothing);
  });

  testWidgets('큰 카드: 막 시각이 된 약(30분 안)은 종전처럼 「다음 약 · 지금」이다', (tester) async {
    await add('혈압약', 8, 0);
    await pumpHome(tester, todayAt(8, 10));

    expect(find.text('지금'), findsOneWidget);
    expect(find.text('다음 약'), findsOneWidget);
    expect(find.text('지난 약'), findsNothing);
  });

  testWidgets('나머지 목록: 지나간 안 먹은 약 줄에 지난 시간이 붙는다', (tester) async {
    await add('혈압약', 8, 0);
    await add('오메가3', 13, 0);
    // 12:50 — 다음 약은 10분 남은 오메가3 이고, 혈압약은 목록으로 내려간다.
    await pumpHome(tester, todayAt(12, 50));

    expect(find.text('10분 남음'), findsOneWidget);
    expect(find.textContaining('4시간 50분 지남'), findsOneWidget);
  });

  testWidgets('나머지 목록: 이미 먹은 약에는 지난 시간을 붙이지 않는다', (tester) async {
    final taken = await add('혈압약', 8, 0);
    await add('오메가3', 13, 0);
    taken.toggleTaken(taken.times.first);
    await pumpHome(tester, todayAt(12, 50));

    expect(find.textContaining('지남'), findsNothing);
    expect(find.textContaining('먹었어요'), findsWidgets);
  });

  testWidgets('나머지 목록: 아직 안 된 약에는 지난 시간을 붙이지 않는다', (tester) async {
    await add('혈압약', 8, 0);
    await add('오메가3', 21, 0);
    // 08:05 — 다음 약은 혈압약(지금), 오메가3 는 저녁이라 목록에 그대로.
    await pumpHome(tester, todayAt(8, 5));

    expect(find.textContaining('지남'), findsNothing);
  });
}
