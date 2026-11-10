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

/// 같은 시각에 먹는 약이 여러 개면 한 번에 「먹었어요」로 표시한다. (T-261110-036)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

  const takeAll = Key('home-take-all-button');

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

  bool taken(Medicine medicine) => medicine.isTaken(medicine.times.first);

  Future<void> pumpHome(
    WidgetTester tester,
    DateTime now, {
    Size size = const Size(390, 1400),
  }) async {
    tester.view.physicalSize = size;
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

  testWidgets('같은 시각에 안 먹은 약이 3개면 큰 카드에 「아침 8:00 약 3개 모두 먹었어요」가 보인다', (
    tester,
  ) async {
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await add('오메가3', 8, 0);
    await add('수면 보조제', 22, 0);
    await pumpHome(tester, todayAt(8, 5));

    expect(find.byKey(takeAll), findsOneWidget);
    expect(find.text('아침 8:00 약 3개 모두 먹었어요'), findsOneWidget);
    // 한 알만 표시하는 원래 단추도 그대로 있다.
    expect(find.byKey(const Key('home-take-button')), findsOneWidget);
  });

  testWidgets('같은 시각 약이 1개뿐이면 「모두 먹었어요」 단추가 없다', (tester) async {
    await add('혈압약', 8, 0);
    await add('오메가3', 13, 0);
    await pumpHome(tester, todayAt(8, 5));

    expect(find.byKey(takeAll), findsNothing);
  });

  testWidgets('같은 시각 약 중 이미 먹은 약은 개수에서 뺀다', (tester) async {
    final first = await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await add('오메가3', 8, 0);
    first.toggleTaken(first.times.first);
    await pumpHome(tester, todayAt(8, 5));

    expect(find.text('아침 8:00 약 2개 모두 먹었어요'), findsOneWidget);
  });

  testWidgets('같은 시각 약 2개 중 1개를 이미 먹었으면 단추가 없다', (tester) async {
    final first = await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    first.toggleTaken(first.times.first);
    await pumpHome(tester, todayAt(8, 5));

    expect(find.byKey(takeAll), findsNothing);
  });

  testWidgets('「모두 먹었어요」를 누르면 그 시각 약만 모두 먹음으로 바뀐다', (tester) async {
    final a = await add('혈압약', 8, 0);
    final b = await add('비타민', 8, 0);
    final c = await add('오메가3', 8, 0);
    final later = await add('수면 보조제', 22, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();

    expect(taken(a), isTrue);
    expect(taken(b), isTrue);
    expect(taken(c), isTrue);
    expect(taken(later), isFalse);
    expect(find.text('오늘 3/4 먹었어요'), findsOneWidget);
    // 다음 차례(저녁 약)로 넘어가면 단추는 사라진다.
    expect(find.byKey(takeAll), findsNothing);
  });

  testWidgets('누른 뒤 안내의 「되돌리기」를 누르면 방금 표시한 약만 되돌아간다', (tester) async {
    final already = await add('혈압약', 8, 0);
    final b = await add('비타민', 8, 0);
    final c = await add('오메가3', 8, 0);
    already.toggleTaken(already.times.first);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('약 2개를 먹었다고 표시했어요'), findsOneWidget);
    expect(taken(b), isTrue);
    expect(taken(c), isTrue);

    await tester.tap(find.text('되돌리기'));
    await tester.pump();

    expect(taken(b), isFalse);
    expect(taken(c), isFalse);
    // 누르기 전에 이미 먹었던 약은 그대로 둔다.
    expect(taken(already), isTrue);

    // 안내가 내려갈 때까지 흘려보낸다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('화면이 바뀌기 전에 두 번 눌러도 먹음 표시가 풀리지 않는다', (tester) async {
    final a = await add('혈압약', 8, 0);
    final b = await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.tap(find.byKey(takeAll), warnIfMissed: false);
    await tester.pump();

    expect(taken(a), isTrue);
    expect(taken(b), isTrue);
  });

  testWidgets('되돌리기 전에 지워진 약이 있어도 나머지는 되돌아간다', (tester) async {
    final a = await add('혈압약', 8, 0);
    final b = await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await a.delete();
    await tester.pump();

    await tester.tap(find.text('되돌리기'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(taken(b), isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('시간이 지난 약 묶음에도 「모두 먹었어요」가 나온다', (tester) async {
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(10, 0));

    expect(find.text('지난 약'), findsOneWidget);
    expect(find.text('아침 8:00 약 2개 모두 먹었어요'), findsOneWidget);
  });

  testWidgets('보통 화면에서 「모두 먹었어요」 단추는 누르기 쉬운 크기(높이 48 이상)다', (tester) async {
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    // 글이 한 줄일 때도 높이를 지킨다.
    expect(
      tester.getSize(find.byKey(takeAll)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('좁은 화면·큰 글씨에서도 단추가 넘치지 않고 누르기 쉬운 크기다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await add('혈압약', 21, 30);
    await add('비타민', 21, 30);
    await add('오메가3', 21, 30);
    await pumpHome(tester, todayAt(21, 0), size: const Size(320, 1400));

    expect(tester.takeException(), isNull);
    expect(find.byKey(takeAll), findsOneWidget);
    expect(
      tester.getSize(find.byKey(takeAll)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('보조 기술에는 「아침 8:00 약 3개 모두 복용 완료로 표시」로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await add('오메가3', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    expect(find.bySemanticsLabel('아침 8:00 약 3개 모두 복용 완료로 표시'), findsOneWidget);
    handle.dispose();
  });
}
