import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/settings_screen.dart';
import 'package:yakmukja/screens/splash_screen.dart';
import 'package:yakmukja/screens/trash_screen.dart';
import 'package:yakmukja/services/iap_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? dir;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.0.7',
      buildNumber: '12',
      buildSignature: '',
    );
  });

  tearDown(() async {
    IapService.adsRemoved.value = false;
    if (Hive.isBoxOpen(medicineBoxName)) {
      await Hive.box<Medicine>(medicineBoxName).close();
    }
    final current = dir;
    if (current != null && current.existsSync()) {
      current.deleteSync(recursive: true);
    }
    dir = null;
  });

  Future<Box<Medicine>> openBox() async {
    final created = await Directory.systemTemp.createTemp('yak_places_');
    dir = created;
    Hive.init(created.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    if (Hive.isBoxOpen(medicineBoxName)) {
      await Hive.box<Medicine>(medicineBoxName).close();
    }
    return Hive.openBox<Medicine>(medicineBoxName);
  }

  Medicine sample(String name, {DateTime? deletedAt}) {
    return Medicine(
      name: name,
      dosage: '1알',
      times: [DoseTime(hour: 8, minute: 0)],
      memo: '',
      createdAt: DateTime(2026, 10, 1),
      deletedAt: deletedAt,
    );
  }

  testWidgets('settings keeps remove-ads purchase and restore rows', (
    tester,
  ) async {
    // 줄이 늘어도(「지난 기록」, T-261110-039) 목록 끝까지 한 화면에 그려지게 한다.
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    );
    await tester.pump();

    expect(find.text('광고 제거'), findsOneWidget);
    expect(find.text('구매 복원'), findsOneWidget);
    expect(find.text('앱 평가하기'), findsOneWidget);
    expect(find.text('피드백 보내기'), findsOneWidget);
    expect(find.text('지난 기록'), findsOneWidget);
    expect(find.text('휴지통'), findsOneWidget);
    expect(find.text('이용약관'), findsOneWidget);
    expect(find.text('개인정보처리방침'), findsOneWidget);

    IapService.adsRemoved.value = true;
    await tester.pump();

    expect(find.text('광고 제거'), findsOneWidget);
    expect(find.text('이미 광고가 제거되어 있어요'), findsOneWidget);
    expect(find.text('구매 복원'), findsOneWidget);
  });

  testWidgets('settings opens terms, privacy, and empty trash', (tester) async {
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(openBox);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('이용약관'));
    await tester.tap(find.text('이용약관'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('1. 서비스 안내'), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('설정'), findsWidgets);

    await tester.ensureVisible(find.text('개인정보처리방침'));
    await tester.tap(find.text('개인정보처리방침'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('1. 수집하지 않는 정보'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('휴지통'));
    await tester.tap(find.text('휴지통'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('휴지통이 비어있어요'), findsOneWidget);
    expect(find.text('삭제한 약은 30일간 보관돼요'), findsWidgets);
  });

  testWidgets('trash restores, permanently deletes, and empties', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Box<Medicine> box;
    await tester.runAsync(() async {
      box = await openBox();
      await box.add(sample('활성약'));
      await box.add(
        sample(
          '비타민D',
          deletedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );
      await box.add(
        sample(
          '오메가3',
          deletedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const TrashScreen()),
    );
    await tester.pump();

    expect(find.text('활성약'), findsNothing);
    expect(find.text('오메가3'), findsOneWidget);
    expect(find.text('비타민D'), findsOneWidget);
    final omegaTop = tester.getTopLeft(find.text('오메가3')).dy;
    final vitaminTop = tester.getTopLeft(find.text('비타민D')).dy;
    expect(omegaTop, lessThan(vitaminTop));

    // 저장·삭제는 디스크를 기다린다. 그 함수를 가짜 시간에서 시작하면
    // 시험이 끝난 뒤 상자 닫기와 서로 기다린다. 버튼 콜백만 진짜 시간에서
    // 시작하고, 대화상자 탭은 시험 시간에서 한다.
    Future<void> press(Finder finder) async {
      await tester.ensureVisible(finder);
      final ink = tester.widget<InkWell>(
        find.ancestor(of: finder, matching: find.byType(InkWell)).first,
      );
      await tester.runAsync(() async {
        ink.onTap!.call();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }

    Future<void> waitDisk() {
      return tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }

    Future<void> showDialogFrame() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await press(find.text('복원').first);
    await waitDisk();
    await tester.pump();
    expect(find.text('오메가3'), findsNothing);
    expect(find.textContaining('복원했어요'), findsOneWidget);
    final restored = box.values.where((m) => m.name == '오메가3').single;
    expect(restored.deletedAt, isNull);
    expect(restored.isInTrash, isFalse);

    await press(find.text('삭제'));
    await showDialogFrame();
    expect(find.text('영구 삭제'), findsOneWidget);
    expect(find.textContaining('복원할 수 없어요.'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await showDialogFrame();
    expect(
      box.values.where((m) => m.name == '비타민D').single.deletedAt,
      isNotNull,
    );

    await press(find.text('삭제'));
    await showDialogFrame();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await waitDisk();
    await showDialogFrame();
    expect(box.values.where((m) => m.name == '비타민D'), isEmpty);
    expect(find.text('휴지통이 비어있어요'), findsOneWidget);

    await tester.runAsync(() async {
      await box.add(
        sample(
          '유산균',
          deletedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      );
      await box.add(
        sample(
          '철분',
          deletedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
    });
    await tester.pump();

    await press(find.text('비우기'));
    await showDialogFrame();
    expect(find.text('휴지통 비우기'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '비우기'));
    await waitDisk();
    await showDialogFrame();
    expect(box.values.where((m) => m.deletedAt != null), isEmpty);
    expect(find.text('휴지통이 비어있어요'), findsOneWidget);
    expect(box.values.where((m) => m.name == '활성약').single.deletedAt, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('splash is a white screen with the centered app icon', (
    tester,
  ) async {
    await tester.runAsync(openBox);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SplashScreen()),
    );
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.white);
    expect(find.byKey(SplashScreen.iconKey), findsOneWidget);
    expect(find.text('건강한 하루의 시작'), findsNothing);
    expect(find.text('약먹자'), findsNothing);

    final icon = tester.getCenter(find.byKey(SplashScreen.iconKey));
    final size = tester.getSize(find.byType(Scaffold));
    expect(icon.dx, closeTo(size.width / 2, 1));
    expect(icon.dy, closeTo(size.height / 2, 1));

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
    expect(find.byKey(SplashScreen.iconKey), findsNothing);
  });

  test('native launch color is white like the splash screen', () {
    final launch = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final launchV21 = File(
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ).readAsStringSync();
    final day = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final night = File(
      'android/app/src/main/res/values-night-v31/styles.xml',
    ).readAsStringSync();
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();

    expect(launch, contains('@android:color/white'));
    expect(launchV21, contains('@android:color/white'));
    expect(day, contains('#FFFFFF'));
    expect(day, isNot(contains('#F7F8FA')));
    expect(night, contains('#FFFFFF'));
    expect(night, isNot(contains('#F7F8FA')));
    expect(storyboard, contains('red="1" green="1" blue="1"'));
    expect(storyboard, isNot(contains('LaunchBackground')));
    expect(storyboard, isNot(contains('LaunchImage')));
  });
}
