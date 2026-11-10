import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/history_screen.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/screens/settings_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 지난 날에 먹은 약을 날짜별로 본다. (T-261110-039)
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
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.1.1',
      buildNumber: '14',
      buildSignature: '',
    );
  });

  tearDownAll(() async {
    await box.close();
  });

  // 화면의 오늘 — 2026-11-10 은 화요일이다.
  DateTime today() => DateTime(2026, 11, 10, 9, 30);

  Future<void> add(
    String name, {
    int hour = 8,
    int minute = 0,
    String dosage = '1알',
    List<String> taken = const [],
    DateTime? createdAt,
  }) => box.add(
    Medicine(
      name: name,
      dosage: dosage,
      times: [DoseTime(hour: hour, minute: minute)],
      memo: '',
      createdAt: createdAt ?? DateTime(2026, 11, 8, 0, 0),
      takenRecords: [...taken],
    ),
  );

  Future<void> pumpHistory(
    WidgetTester tester, {
    Size size = const Size(390, 2400),
    double textScale = 1,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HistoryScreen(clock: today),
      ),
    );
    await tester.pump();
  }

  Finder inDay(String key, Finder matching) => find.descendant(
    of: find.byKey(Key('history-day-$key')),
    matching: matching,
  );

  testWidgets('어제 묶음에 날짜·「1/2 먹었어요」·약 줄이 보인다', (tester) async {
    await add('혈압약', taken: ['2026-11-09_08:00']);
    await add('수면 보조제', hour: 21, minute: 30);
    await pumpHistory(tester);

    expect(find.text('지난 기록'), findsOneWidget);
    expect(inDay('2026-11-09', find.text('어제 · 11월 9일 월요일')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('1/2 먹었어요')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('혈압약')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('아침 8:00 · 1알')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('먹었어요')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('수면 보조제')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('저녁 9:30 · 1알')), findsOneWidget);
    expect(inDay('2026-11-09', find.text('기록 없음')), findsOneWidget);
  });

  testWidgets('그제부터는 「어제」 머리표 없이 날짜만 보인다', (tester) async {
    await add('혈압약');
    await pumpHistory(tester);

    expect(inDay('2026-11-08', find.text('11월 8일 일요일')), findsOneWidget);
    expect(inDay('2026-11-08', find.text('0/1 먹었어요')), findsOneWidget);
  });

  testWidgets('복용량이 없는 약은 시각만 보인다', (tester) async {
    await add('혈압약', dosage: '');
    await pumpHistory(tester);

    expect(inDay('2026-11-09', find.text('아침 8:00')), findsOneWidget);
  });

  testWidgets('지난 기록이 없으면 빈 화면 안내가 보인다', (tester) async {
    // 오늘 등록한 약 — 지난 날이 없다.
    await add('혈압약', createdAt: DateTime(2026, 11, 10, 8, 0));
    await pumpHistory(tester);

    expect(find.text('아직 지난 기록이 없어요'), findsOneWidget);
    expect(find.byKey(const Key('history-day-2026-11-09')), findsNothing);
  });

  testWidgets('기록이 남는 기간을 알려 준다', (tester) async {
    await add('혈압약');
    await pumpHistory(tester);

    expect(find.textContaining('최근 30일'), findsWidgets);
  });

  testWidgets('뒤로 단추를 누르면 앞 화면으로 돌아간다', (tester) async {
    await add('혈압약');
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryScreen(clock: today),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('지난 기록'), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();

    expect(find.text('지난 기록'), findsNothing);
    expect(find.text('열기'), findsOneWidget);
  });

  for (final (width, scale) in [(320.0, 1.3), (320.0, 2.0), (360.0, 2.0)]) {
    testWidgets('폭 $width·글씨 $scale배에서도 넘치지 않는다', (tester) async {
      await add('종합비타민 미네랄', dosage: '2캡슐', taken: ['2026-11-09_08:00']);
      await add('수면 보조제', hour: 21, minute: 30, dosage: '10방울');
      await pumpHistory(tester, size: Size(width, 3000), textScale: scale);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('보조 기술에는 한 줄이 시각·이름·복용량·상태로 이어 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await add('혈압약', taken: ['2026-11-09_08:00']);
    await pumpHistory(tester);

    expect(find.bySemanticsLabel('아침 8:00 혈압약 1알 먹었어요'), findsOneWidget);
    expect(find.bySemanticsLabel('아침 8:00 혈압약 1알 기록 없음'), findsOneWidget);
    handle.dispose();
  });

  group('들어가는 길', () {
    testWidgets('설정의 「지난 기록」을 누르면 화면이 열린다', (tester) async {
      tester.view.physicalSize = const Size(402, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('지난 기록'));
      await tester.tap(find.text('지난 기록'));
      await tester.pumpAndSettle();

      expect(find.textContaining('최근 30일'), findsWidgets);
      expect(find.byTooltip('뒤로'), findsOneWidget);
    });

    testWidgets('홈 머리말(날짜 줄)을 누르면 지난 기록이 열린다', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await add('혈압약');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(clock: today),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('home-history-link')));
      await tester.pumpAndSettle();

      expect(find.text('지난 기록'), findsOneWidget);
    });

    testWidgets('홈 머리말은 단추이고 누르면 지난 기록이 열린다고 알려 준다', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await add('혈압약');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(clock: today),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.byKey(const Key('home-history-link')),
      );
      expect(node.label, contains('11월 10일 화요일'));
      expect(node.label, contains('지난 기록 보기'));
      expect(node, containsSemantics(isButton: true, hasTapAction: true));
      handle.dispose();
    });

    testWidgets('약이 하나도 없는 첫 화면에도 날짜 줄은 그대로 보인다', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(clock: today),
        ),
      );
      await tester.pump();

      expect(find.text('11월 10일 화요일'), findsOneWidget);
      expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
    });
  });
}
