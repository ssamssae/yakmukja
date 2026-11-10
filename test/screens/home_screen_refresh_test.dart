import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 홈 화면은 약 저장이 바뀔 때만이 아니라 시간이 흐를 때도 다시 그려져야 한다.
/// (T-261110-020 — 앱을 끄지 않고 다시 열면 어제 화면이 그대로 남던 문제)
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
    await box.clear();
    await box.add(
      Medicine(
        name: '혈압약',
        dosage: '1알',
        times: [DoseTime(hour: 8, minute: 0), DoseTime(hour: 21, minute: 30)],
        memo: '',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
  });

  tearDownAll(() async {
    await box.close();
  });

  Future<void> pumpHome(WidgetTester tester, DateTime Function() clock) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: clock),
      ),
    );
    await tester.pump();
  }

  testWidgets('앱이 다시 앞으로 오면 홈이 지금 날짜와 시각으로 다시 그려진다', (tester) async {
    var now = DateTime(2026, 11, 10, 21, 0);
    await pumpHome(tester, () => now);
    expect(find.text('11월 10일 화요일'), findsOneWidget);
    expect(find.text('30분 남음'), findsOneWidget);

    // 밤 9시에 닫았다가 다음 날 아침 8시에 다시 연다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 11, 11, 8, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('11월 11일 수요일'), findsOneWidget);
    expect(find.text('지금'), findsOneWidget);
    expect(find.text('30분 남음'), findsNothing);
  });

  testWidgets('앱을 켜 둔 채 1분이 지나면 남은 시간이 줄어든다', (tester) async {
    var now = DateTime(2026, 11, 10, 21, 0);
    await pumpHome(tester, () => now);
    expect(find.text('30분 남음'), findsOneWidget);

    now = DateTime(2026, 11, 10, 21, 1, 1);
    await tester.pump(const Duration(seconds: 61));

    expect(find.text('29분 남음'), findsOneWidget);
    expect(find.text('30분 남음'), findsNothing);
  });

  testWidgets('앱을 켜 둔 채 복용 시각이 되면 큰 카드가 「지금」으로 바뀐다', (tester) async {
    var now = DateTime(2026, 11, 10, 21, 29);
    await pumpHome(tester, () => now);
    expect(find.text('1분 남음'), findsOneWidget);
    expect(find.text('저녁 9:30에 알림을 보내드릴게요'), findsOneWidget);

    now = DateTime(2026, 11, 10, 21, 30, 1);
    await tester.pump(const Duration(seconds: 61));

    expect(find.text('지금'), findsOneWidget);
    expect(find.text('저녁 9:30에 알림을 보내드릴게요'), findsNothing);
  });
}
