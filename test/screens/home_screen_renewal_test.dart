import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';
import 'package:yakmukja/widgets/renewal_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

  setUpAll(() async {
    // 메모리 박스. 위젯 시험의 가짜 시계 안에서 디스크 잠금이 다음 시험을 멈추지 않게 한다.
    Hive.init(Directory.systemTemp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  tearDownAll(() async {
    await box.close();
  });

  group('pickNextDoseIndex', () {
    test('picks the untaken dose closest to now', () {
      final doses = [
        (minuteOfDay: 8 * 60, taken: true),
        (minuteOfDay: 8 * 60 + 30, taken: false),
        (minuteOfDay: 21 * 60 + 30, taken: false),
      ];

      expect(pickNextDoseIndex(doses, 8 * 60 + 10), 1);
    });

    test('a nearer later dose wins over an earlier missed dose', () {
      final doses = [
        (minuteOfDay: 8 * 60, taken: false),
        (minuteOfDay: 21 * 60 + 30, taken: false),
      ];

      expect(pickNextDoseIndex(doses, 20 * 60), 1);
    });

    test('equal gaps keep the earlier dose', () {
      final doses = [
        (minuteOfDay: 8 * 60 + 30, taken: false),
        (minuteOfDay: 21 * 60 + 30, taken: false),
      ];

      expect(pickNextDoseIndex(doses, 15 * 60), 0);
    });

    test('returns null when every dose is taken or the list is empty', () {
      expect(
        pickNextDoseIndex([(minuteOfDay: 8 * 60, taken: true)], 8 * 60),
        isNull,
      );
      expect(pickNextDoseIndex(const [], 8 * 60), isNull);
    });
  });

  test('dose remain text and period labels', () {
    expect(doseRemainText(8 * 60 + 30, 8 * 60 + 10), '20분 남음');
    expect(doseRemainText(10 * 60, 8 * 60 + 30), '1시간 30분 남음');
    expect(doseRemainText(10 * 60, 8 * 60), '2시간 남음');
    expect(doseRemainText(8 * 60, 8 * 60), '지금');
    expect(doseRemainText(8 * 60, 9 * 60), '지금');
    expect(homePeriodLabel(5), '새벽');
    expect(homePeriodLabel(6), '아침');
    expect(homePeriodLabel(11), '아침');
    expect(homePeriodLabel(12), '오후');
    expect(homePeriodLabel(18), '저녁');
    expect(homeClockLabel(0, 5), '12:05');
    expect(homeClockLabel(21, 30), '9:30');
  });

  testWidgets('empty home asks to register and hides the ad removal icon', (
    tester,
  ) async {
    await _seed(const []);
    await _pumpHome(tester, _todayAt(8, 10));

    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
    expect(find.text('아래 + 약등록을 눌러\n약을 추가해 보세요'), findsOneWidget);
    expect(find.byKey(const Key('home-empty')), findsOneWidget);
    expect(find.byKey(const Key('home-take-button')), findsNothing);
    expect(find.byKey(const Key('home-all-done')), findsNothing);
    expect(find.byIcon(Icons.block), findsNothing);
    expect(find.byTooltip('광고 제거'), findsNothing);
    expect(find.text('광고 제거'), findsNothing);
  });

  testWidgets('next card is the closest untaken dose and 먹었어요 records it', (
    tester,
  ) async {
    final now = DateTime.now();
    final day = _day(now);
    await _seed([
      Medicine(
        name: '비타민D',
        dosage: '1알',
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: now,
        takenRecords: ['${day}_08:00'],
      ),
      Medicine(
        name: '오메가3',
        dosage: '2알',
        times: [DoseTime(hour: 8, minute: 30)],
        memo: '',
        createdAt: now,
      ),
      Medicine(
        name: '유산균',
        dosage: '1포',
        times: [DoseTime(hour: 21, minute: 30)],
        memo: '',
        createdAt: now,
      ),
    ]);
    await _pumpHome(tester, _todayAt(8, 10));

    expect(find.text('오늘 1/3 먹었어요'), findsOneWidget);
    expect(find.text('20분 남음'), findsOneWidget);
    expect(find.text('아침 8:30'), findsOneWidget);
    final nextName = tester.widget<Text>(find.text('오메가3'));
    expect(nextName.style?.fontSize, 40);
    expect(find.text('오늘 나머지'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsNothing);

    await tester.tap(find.text('먹었어요'));
    await tester.pump();

    final omega = Hive.box<Medicine>(
      medicineBoxName,
    ).values.firstWhere((medicine) => medicine.name == '오메가3');
    expect(omega.isTaken(omega.times.single), isTrue);
    expect(find.text('오늘 2/3 먹었어요'), findsOneWidget);
    expect(find.text('저녁 9:30'), findsWidgets);
  });

  testWidgets('a later dose becomes next when it is closer than a missed one', (
    tester,
  ) async {
    final now = DateTime.now();
    await _seed([
      Medicine(
        name: '아침약',
        dosage: '1알',
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: now,
      ),
      Medicine(
        name: '저녁약',
        dosage: '1알',
        times: [DoseTime(hour: 21, minute: 30)],
        memo: '',
        createdAt: now,
      ),
    ]);
    await _pumpHome(tester, _todayAt(20, 0));

    final nextName = tester.widget<Text>(find.text('저녁약'));
    expect(nextName.style?.fontSize, 40);
    final missed = tester.widget<Text>(find.text('아침약'));
    expect(missed.style?.fontSize, 16);
    expect(find.text('1시간 30분 남음'), findsOneWidget);
  });

  testWidgets('all taken doses replace the next card and a check undoes one', (
    tester,
  ) async {
    final now = DateTime.now();
    final day = _day(now);
    await _seed([
      Medicine(
        name: '비타민D',
        dosage: '1알',
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: now,
        takenRecords: ['${day}_08:00'],
      ),
      Medicine(
        name: '오메가3',
        dosage: '2알',
        times: [DoseTime(hour: 8, minute: 30)],
        memo: '',
        createdAt: now,
        takenRecords: ['${day}_08:30'],
      ),
    ]);
    await _pumpHome(tester, _todayAt(8, 10));

    expect(find.text('오늘 약을 다 먹었어요'), findsOneWidget);
    expect(find.byKey(const Key('home-all-done')), findsOneWidget);
    expect(find.byKey(const Key('home-take-button')), findsNothing);
    expect(find.text('오늘 2/2 먹었어요'), findsOneWidget);
    expect(find.bySemanticsLabel('비타민D 아침 8:00 복용 완료 취소'), findsOneWidget);

    await tester.tap(find.byType(RenewalCheck).first);
    await tester.pump();

    final vitamin = Hive.box<Medicine>(
      medicineBoxName,
    ).values.firstWhere((medicine) => medicine.name == '비타민D');
    expect(vitamin.isTaken(vitamin.times.single), isFalse);
    expect(find.byKey(const Key('home-take-button')), findsOneWidget);
    expect(find.text('오늘 약을 다 먹었어요'), findsNothing);
  });
}

DateTime _todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

String _day(DateTime now) {
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

Future<void> _seed(List<Medicine> meds) async {
  final box = Hive.box<Medicine>(medicineBoxName);
  await box.clear();
  if (meds.isNotEmpty) await box.addAll(meds);
}

Future<void> _pumpHome(WidgetTester tester, DateTime clock) async {
  tester.view.physicalSize = const Size(402, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: HomeScreen(clock: () => clock),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}
