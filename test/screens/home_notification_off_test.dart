import 'dart:async';
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

import '../support/fake_notification_center.dart';

/// 알림이 꺼져 있으면 홈이 그 사실을 알리고 켤 길을 준다. (T-261110-026)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

  // 저녁 9:30 약이 「다음 약」이 되는 시각.
  DateTime evening() => DateTime(2026, 11, 10, 21, 0);

  setUpAll(() async {
    Hive.init(Directory.systemTemp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  setUp(() async {
    // 알림 서비스는 앱 전체에서 하나다. 시험마다 처음 상태에서 시작한다.
    NotificationService.resetForTest();
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
  });

  Future<void> addMedicine() => box.add(
    Medicine(
      name: '혈압약',
      dosage: '1알',
      times: [DoseTime(hour: 21, minute: 30)],
      memo: '',
      createdAt: DateTime(2026, 11, 1),
    ),
  );

  /// 권한 확인·알림 맞추기처럼 화면 밖에서 이어지는 일을 끝까지 흘려보낸다.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: evening),
      ),
    );
    await tester.pump();
  }

  testWidgets('알림이 꺼져 있고 약이 있으면 꺼짐 안내와 「알림 켜기」가 보이고 알림 예고는 사라진다', (
    tester,
  ) async {
    await addMedicine();
    NotificationService.enabled.value = false;
    await pumpHome(tester);

    expect(find.text('알림이 꺼져 있어요'), findsOneWidget);
    expect(find.text('알림 켜기'), findsOneWidget);
    expect(find.text('저녁 9:30에 알림을 보내드릴게요'), findsNothing);
  });

  testWidgets('좁은 화면에서도 꺼짐 안내 제목이 한 줄이고 「알림 켜기」는 글 아래에 있다', (tester) async {
    await addMedicine();
    NotificationService.enabled.value = false;
    await pumpHome(tester, size: const Size(320, 568));

    final title = find.text('알림이 꺼져 있어요');
    final note = find.text('약 먹을 시간에 알려드리지 못해요');
    final button = find.text('알림 켜기');
    // 제목 글자는 16pt 다. 두 줄 높이가 되면 줄이 꺾인 것이다.
    expect(tester.getSize(title).height, lessThan(16 * 2));
    // 단추가 글 옆에 있으면 글 칸이 좁아져 「…있어 / 요」처럼 꺾인다.
    expect(
      tester.getTopLeft(button).dy,
      greaterThan(tester.getBottomLeft(note).dy),
    );
  });

  testWidgets('알림이 켜져 있으면 꺼짐 안내는 없고 알림 예고가 보인다', (tester) async {
    await addMedicine();
    NotificationService.enabled.value = true;
    await pumpHome(tester);

    expect(find.text('알림이 꺼져 있어요'), findsNothing);
    expect(find.text('저녁 9:30에 알림을 보내드릴게요'), findsOneWidget);
  });

  testWidgets('약이 하나도 없으면 알림이 꺼져 있어도 꺼짐 안내를 띄우지 않는다', (tester) async {
    NotificationService.enabled.value = false;
    await pumpHome(tester);

    expect(find.text('알림이 꺼져 있어요'), findsNothing);
    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
  });

  testWidgets('기기 설정에서 알림을 켜고 앱으로 돌아오면 꺼짐 안내가 사라진다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    try {
      center
        ..enabled = false
        ..grantOnRequest = false;
      await addMedicine();
      await tester.runAsync(
        () => NotificationService.initAndSync(() => box.values),
      );
      await pumpHome(tester);
      expect(find.text('알림이 꺼져 있어요'), findsOneWidget);

      center.enabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(find.text('알림이 꺼져 있어요'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      center.uninstall();
    }
  });

  testWidgets('「알림 켜기」를 눌러 허용하면 꺼짐 안내가 사라진다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.android);
    try {
      center
        ..enabled = false
        ..grantOnRequest = false;
      await addMedicine();
      await tester.runAsync(
        () => NotificationService.initAndSync(() => box.values),
      );
      await pumpHome(tester);
      center.grantOnRequest = true;

      await tester.tap(find.text('알림 켜기'));
      await settle(tester);

      expect(find.text('알림이 꺼져 있어요'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      center.uninstall();
    }
  });

  testWidgets('안드로이드에서 「알림 켜기」로도 못 켜면 설정에서 켜는 길을 알려 준다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.android);
    try {
      center
        ..enabled = false
        ..grantOnRequest = false;
      await addMedicine();
      await tester.runAsync(
        () => NotificationService.initAndSync(() => box.values),
      );
      await pumpHome(tester);

      await tester.tap(find.text('알림 켜기'));
      await settle(tester);

      expect(find.text('알림이 꺼져 있어요'), findsOneWidget);
      expect(find.textContaining('알림을 켜 주세요'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      center.uninstall();
    }
  });

  testWidgets('알림이 꺼져 있으면 약 등록 화면도 알림이 발송된다고 말하지 않는다', (tester) async {
    await addMedicine();
    NotificationService.enabled.value = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicineEditScreen(medicine: box.values.first),
      ),
    );
    await tester.pump();

    expect(find.text('설정된 시간에 푸시 알림이 발송됩니다'), findsNothing);
    expect(find.text('알림이 꺼져 있어요. 홈에서 알림을 켜 주세요'), findsOneWidget);
    // 요일 안내도 알림을 받는다고 말하지 않는다.
    expect(find.text('매일 알림을 받아요'), findsNothing);
    expect(find.text('매일 먹는 약이에요'), findsOneWidget);
  });

  testWidgets('알림 상태를 아직 모르면 약 등록 화면은 종전 문구이고, 꺼짐을 알게 되면 바로 바뀐다', (
    tester,
  ) async {
    await addMedicine();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicineEditScreen(medicine: box.values.first),
      ),
    );
    await tester.pump();
    expect(find.text('설정된 시간에 푸시 알림이 발송됩니다'), findsOneWidget);
    expect(find.text('매일 알림을 받아요'), findsOneWidget);

    NotificationService.enabled.value = false;
    await tester.pump();

    expect(find.text('알림이 꺼져 있어요. 홈에서 알림을 켜 주세요'), findsOneWidget);
    expect(find.text('매일 먹는 약이에요'), findsOneWidget);
  });

  testWidgets('오늘 쉬는 약만 있어도 꺼짐 안내가 나온다', (tester) async {
    // 시험 시각(2026-11-10)은 화요일이다. 수요일에만 먹는 약.
    await box.add(
      Medicine(
        name: '골다공증약',
        dosage: '1알',
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: DateTime(2026, 11, 1),
        weekdays: [DateTime.wednesday],
      ),
    );
    NotificationService.enabled.value = false;
    await pumpHome(tester);

    expect(find.text('알림이 꺼져 있어요'), findsOneWidget);
  });

  testWidgets('「알림 켜기」 단추는 누르기 쉬운 크기다 — 높이 48 이상', (tester) async {
    await addMedicine();
    NotificationService.enabled.value = false;
    await pumpHome(tester);

    final button = find.ancestor(
      of: find.text('알림 켜기'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });

  testWidgets('꺼진 채로 앱에 여러 번 돌아와도 권한을 다시 묻거나 설정 화면을 열지 않는다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    try {
      center
        ..enabled = false
        ..grantOnRequest = false;
      await addMedicine();
      await tester.runAsync(
        () => NotificationService.initAndSync(() => box.values),
      );
      await pumpHome(tester);
      int asked() =>
          center.methods.where((m) => m == 'requestPermissions').length;
      final askedBefore = asked();

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
      }

      expect(asked(), askedBefore);
      expect(center.launchedUrls, isEmpty);
      expect(find.text('알림이 꺼져 있어요'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      center.uninstall();
    }
  });

  testWidgets('「알림 켜기」를 두 번 눌러도 권한은 한 번만 묻는다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.android);
    final gate = Completer<void>();
    try {
      center
        ..enabled = false
        ..grantOnRequest = false;
      await addMedicine();
      await tester.runAsync(
        () => NotificationService.initAndSync(() => box.values),
      );
      await pumpHome(tester);
      int asked() => center.methods
          .where((m) => m == 'requestNotificationsPermission')
          .length;
      final askedBefore = asked();

      // 권한 창이 떠 있는 동안(답이 아직 안 옴) 한 번 더 누른다.
      center.hold = gate.future;
      await tester.tap(find.text('알림 켜기'));
      await tester.pump();
      await tester.tap(find.text('알림 켜기'));
      await tester.pump();
      center.hold = null;
      gate.complete();
      await settle(tester);

      expect(asked() - askedBefore, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      // 첫 안내가 내려간 뒤에 같은 안내가 한 번 더 올라오지 않는다.
      await tester.pump(const Duration(seconds: 1)); // 올라오는 움직임이 끝난다
      await tester.pump(const Duration(seconds: 5)); // 4초 뒤 내려가기 시작한다
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      center.uninstall();
    }
  });

  testWidgets('iOS 에서 설정 화면을 열었으면 안내 글은 띄우지 않는다', (tester) async {
    final center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    try {
      center
        ..enabled = false
        ..grantOnRequest = false;
      await addMedicine();
      await tester.runAsync(
        () => NotificationService.initAndSync(() => box.values),
      );
      await pumpHome(tester);

      await tester.tap(find.text('알림 켜기'));
      await settle(tester);

      expect(center.launchedUrls, ['app-settings:']);
      expect(find.byType(SnackBar), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      center.uninstall();
    }
  });
}
