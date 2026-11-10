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
  });
}
