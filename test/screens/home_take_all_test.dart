import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/screens/main_shell.dart';
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

    expect(find.text('아침 8:00 약 2개를 먹었다고 표시했어요'), findsOneWidget);
    expect(taken(b), isTrue);
    expect(taken(c), isTrue);

    await tester.tap(find.text('되돌리기'));
    await tester.pump();

    expect(taken(b), isFalse);
    expect(taken(c), isFalse);
    // 누르기 전에 이미 먹었던 약은 그대로 둔다.
    expect(taken(already), isTrue);

    // 「되돌리기」를 눌러 닫히는 애니메이션을 흘려보낸다.
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

  testWidgets('안내는 몇 초 뒤 스스로 내려간다', (tester) async {
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('되돌리기'), findsOneWidget);

    // 계속 남아 있으면 다른 화면의 단추를 가리고 다른 안내도 막는다.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('되돌리기'), findsNothing);
  });

  testWidgets('화면 읽기 탐색을 쓰면 안내가 스스로 내려가지 않고 닫기 단추가 있다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('되돌리기'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('되돌리기'), findsNothing);
  });

  testWidgets('누른 직후 같은 자리를 또 눌러도 다음 시각 약은 표시되지 않는다', (tester) async {
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    final evening1 = await add('오메가3', 20, 0);
    final evening2 = await add('유산균', 20, 0);
    await pumpHome(tester, todayAt(8, 5));

    final spot = tester.getCenter(find.byKey(takeAll));
    await tester.tapAt(spot);
    // 화면이 바뀌어 같은 자리에 저녁 약의 「모두 먹었어요」가 올라온다.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('저녁 8:00 약 2개 모두 먹었어요'), findsOneWidget);
    await tester.tapAt(spot);
    await tester.pump();

    expect(taken(evening1), isFalse);
    expect(taken(evening2), isFalse);

    // 잠깐 뒤에는 다시 누를 수 있다.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tapAt(spot);
    await tester.pump();

    expect(taken(evening1), isTrue);
    expect(taken(evening2), isTrue);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });

  testWidgets('「먹었어요」를 연달아 눌러도 다음 약은 표시되지 않는다', (tester) async {
    final morning = await add('혈압약', 8, 0);
    final evening = await add('오메가3', 20, 0);
    await pumpHome(tester, todayAt(8, 5));

    final spot = tester.getCenter(find.byKey(const Key('home-take-button')));
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tapAt(spot);
    await tester.pump();

    expect(taken(morning), isTrue);
    expect(taken(evening), isFalse);

    // 반 초쯤 지나면 다음 약을 누를 수 있다.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(spot);
    await tester.pump();

    expect(taken(evening), isTrue);
  });

  testWidgets('되돌리기 전에 손으로 되돌린 약은 다시 먹음으로 바뀌지 않는다', (tester) async {
    final a = await add('혈압약', 8, 0);
    final b = await add('비타민', 8, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // 하나를 손으로 되돌린다.
    a.toggleTaken(a.times.first);
    await tester.pump();
    expect(taken(a), isFalse);

    await tester.tap(find.text('되돌리기'));
    await tester.pump();

    expect(taken(a), isFalse);
    expect(taken(b), isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('두 묶음을 이어서 표시하면 안내는 마지막 것만 남는다', (tester) async {
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await add('오메가3', 20, 0);
    await add('유산균', 20, 0);
    await pumpHome(tester, todayAt(8, 5));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('저녁 8:00 약 2개를 먹었다고 표시했어요'), findsOneWidget);
    expect(find.text('아침 8:00 약 2개를 먹었다고 표시했어요'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });

  testWidgets('바닥 메뉴가 있는 실제 화면에서도 안내는 메뉴 위에 떴다가 스스로 내려가고, 그 뒤 다른 안내가 뜬다', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.1.1',
      buildNumber: '14',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await add('혈압약', 8, 0);
    await add('비타민', 8, 0);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MainShell()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(takeAll));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('되돌리기'), findsOneWidget);
    // 안내가 바닥 메뉴를 덮지 않는다.
    expect(
      tester.getRect(find.byType(SnackBar)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('약목록')).top),
    );

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('되돌리기'), findsNothing);

    // 안내가 남아 있으면 뒤에 오는 안내는 줄만 서고 보이지 않는다.
    ScaffoldMessenger.of(
      tester.element(find.byType(MainShell)),
    ).showSnackBar(const SnackBar(content: Text('다른 안내')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('다른 안내'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
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

    final button = find.bySemanticsLabel('아침 8:00 약 3개 모두 복용 완료로 표시');
    expect(button, findsOneWidget);
    // 글만이 아니라 「누를 수 있는 단추」로 알려져야 한다.
    expect(
      tester.getSemantics(button),
      isSemantics(isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
