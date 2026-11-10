import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

import '../support/fake_notification_center.dart';

/// 끝나는 날이 지난 약은 오늘 목록·쉬는 약에서 빠지고 「끝난 약」에 남는다.
/// (T-261110-042)
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
    NotificationService.resetForTest();
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
  });

  Medicine med(
    String name, {
    List<int>? weekdays,
    DateTime? endDate,
    DateTime? deletedAt,
    List<DoseTime>? times,
  }) => Medicine(
    name: name,
    dosage: '1알',
    times: times ?? [DoseTime(hour: 8, minute: 0)],
    memo: '',
    createdAt: DateTime(2026, 11, 1),
    weekdays: weekdays,
    endDate: endDate,
    deletedAt: deletedAt,
  );

  Future<void> pumpHome(
    WidgetTester tester, {
    DateTime Function()? clock,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: clock ?? tuesday),
      ),
    );
    await tester.pump();
  }

  testWidgets('끝나는 날이 어제 이전인 약은 오늘 목록에 없고 끝난 약 목록에 있다', (tester) async {
    await box.add(med('혈압약'));
    await box.add(med('항생제', endDate: DateTime(2026, 11, 9, 21, 0)));
    await pumpHome(tester);

    expect(find.text('오늘 0/1 먹었어요'), findsOneWidget);
    expect(find.text('혈압약'), findsOneWidget);
    expect(find.text('끝난 약'), findsOneWidget);
    expect(find.text('항생제'), findsOneWidget);
    expect(find.text('오늘 쉬는 약'), findsNothing);
  });

  testWidgets('끝나는 날이 오늘인 약은 오늘 목록에 남는다', (tester) async {
    await box.add(med('항생제', endDate: DateTime(2026, 11, 10, 23, 59)));
    await pumpHome(tester);

    expect(find.text('오늘 0/1 먹었어요'), findsOneWidget);
    expect(find.text('항생제'), findsOneWidget);
    expect(find.text('끝난 약'), findsNothing);
  });

  testWidgets('끝난 약은 오늘 쉬는 약 목록에 들어가지 않는다', (tester) async {
    await box.add(med('주사', weekdays: [3], endDate: DateTime(2026, 11, 4)));
    await pumpHome(tester);

    expect(find.text('오늘 쉬는 약'), findsNothing);
    expect(find.text('끝난 약'), findsOneWidget);
    expect(find.text('주사'), findsOneWidget);
    expect(find.text('아직 등록된 약이 없어요'), findsNothing);
    expect(find.text('오늘은 먹을 약이 없어요'), findsOneWidget);
  });

  testWidgets('아직 끝나지 않은 쉬는 약은 쉬는 약 목록에 남는다', (tester) async {
    await box.add(med('주사', weekdays: [3], endDate: DateTime(2026, 11, 12)));
    await pumpHome(tester);

    expect(find.text('오늘 쉬는 약'), findsOneWidget);
    expect(find.text('끝난 약'), findsNothing);
    expect(find.text('주사'), findsOneWidget);
  });

  testWidgets('끝난 약을 누르면 수정 화면이 열린다', (tester) async {
    await box.add(med('항생제', endDate: DateTime(2026, 11, 9)));
    await pumpHome(tester);

    await tester.tap(find.text('항생제'));
    await tester.pumpAndSettle();

    expect(find.text('약 수정'), findsOneWidget);
    expect(find.text('2026년 11월 9일'), findsOneWidget);
  });

  testWidgets('휴지통에 있는 끝난 약은 목록에 나오지 않는다', (tester) async {
    await box.add(
      med(
        '버린약',
        endDate: DateTime(2026, 11, 1),
        deletedAt: DateTime(2026, 11, 9),
      ),
    );
    await pumpHome(tester);

    expect(find.text('버린약'), findsNothing);
    expect(find.text('끝난 약'), findsNothing);
    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
  });

  testWidgets('끝나는 날이 없는 약만 있으면 끝난 약 목록은 나오지 않는다', (tester) async {
    await box.add(med('혈압약'));
    await pumpHome(tester);

    expect(find.text('오늘 0/1 먹었어요'), findsOneWidget);
    expect(find.text('끝난 약'), findsNothing);
  });

  Future<void> resumeApp(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('같은 날 다시 앞으로 오면 알림을 다시 걸지 않는다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    try {
      var now = DateTime(2099, 1, 5, 10, 0);
      NotificationService.clock = () => now;
      await box.add(
        med(
          '항생제',
          endDate: DateTime(2099, 1, 5),
          times: [DoseTime(hour: 21, minute: 0)],
        ),
      );
      await NotificationService.initAndSync(() => box.values);
      expect(center.onceAlarms, ['2099-01-05 21:00 드실 약이 있어요.']);
      center.methods.clear();

      await pumpHome(tester, clock: () => now);
      await resumeApp(tester);

      expect(center.methods, isNot(contains('cancelAllPendingNotifications')));
      expect(center.onceAlarms, ['2099-01-05 21:00 드실 약이 있어요.']);
    } finally {
      center.uninstall();
      NotificationService.resetForTest();
    }
  });

  testWidgets('다음 날 다시 앞으로 오면 끝난 약의 알림을 다시 맞춘다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    try {
      var now = DateTime(2099, 1, 5, 10, 0);
      NotificationService.clock = () => now;
      await box.add(
        med(
          '항생제',
          endDate: DateTime(2099, 1, 5),
          times: [DoseTime(hour: 21, minute: 0)],
        ),
      );
      await NotificationService.initAndSync(() => box.values);
      expect(center.onceAlarms, ['2099-01-05 21:00 드실 약이 있어요.']);
      center.methods.clear();

      await pumpHome(tester, clock: () => now);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2099, 1, 6, 8, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(center.methods, contains('cancelAllPendingNotifications'));
      expect(center.onceAlarms, isEmpty);
      expect(find.text('끝난 약'), findsOneWidget);
      expect(find.text('항생제'), findsOneWidget);
      expect(find.text('오늘 0/1 먹었어요'), findsNothing);
    } finally {
      center.uninstall();
      NotificationService.resetForTest();
    }
  });

  testWidgets('켜 둔 채 날짜가 바뀌면 알림을 다시 맞춘다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    try {
      var now = DateTime(2099, 1, 5, 23, 59);
      NotificationService.clock = () => now;
      await box.add(med('항생제', endDate: DateTime(2099, 1, 5)));
      await NotificationService.initAndSync(() => box.values);
      center.methods.clear();

      await pumpHome(tester, clock: () => now);
      expect(find.text('오늘 0/1 먹었어요'), findsOneWidget);

      now = DateTime(2099, 1, 6, 0, 0, 1);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();

      expect(center.methods, contains('cancelAllPendingNotifications'));
      expect(center.onceAlarms, isEmpty);
      expect(find.text('끝난 약'), findsOneWidget);
      expect(find.text('오늘 0/1 먹었어요'), findsNothing);
    } finally {
      center.uninstall();
      NotificationService.resetForTest();
    }
  });
}
