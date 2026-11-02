import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/main_shell.dart';
import 'package:yakmukja/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.0.7',
      buildNumber: '12',
      buildSignature: '',
    );
  });

  testWidgets('dock opens the medicine list, register form, and settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('yak_shell_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(MedicineAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(DoseTimeAdapter());
      }
      if (Hive.isBoxOpen(medicineBoxName)) {
        await Hive.box<Medicine>(medicineBoxName).close();
      }
      final box = await Hive.openBox<Medicine>(medicineBoxName);
      await box.clear();
    });
    addTearDown(() async {
      if (Hive.isBoxOpen(medicineBoxName)) {
        await Hive.box<Medicine>(medicineBoxName).close();
      }
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MainShell()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    expect(find.text('약목록'), findsOneWidget);
    expect(find.text('약등록'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsNothing);
    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('앱 평가하기'), findsOneWidget);
    expect(find.text('광고 제거'), findsOneWidget);
    expect(find.text('구매 복원'), findsOneWidget);

    await tester.tap(find.text('약목록'));
    await tester.pump();
    expect(find.text('아직 등록된 약이 없어요'), findsOneWidget);
    expect(find.text('앱 평가하기'), findsNothing);

    await tester.tap(find.text('약등록'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('약 등록'), findsOneWidget);
    expect(find.text('복용 시간 추가하기'), findsOneWidget);
  });
}
