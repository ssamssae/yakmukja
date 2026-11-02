import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';
import 'package:yakmukja/theme/renewal_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toss tone tokens keep brand green and drop the old body gray', () {
    expect(AppColors.textBody, const Color(0xFF4E5968));
    expect(AppColors.textStrong, const Color(0xFF191F28));
    expect(AppColors.textFaint, const Color(0xFF8B95A1));
    expect(AppColors.bg, const Color(0xFFF2F4F6));
    expect(AppColors.primary, const Color(0xFF22C55E));
    expect(AppColors.primaryDark, const Color(0xFF16A34A));
    expect(AppColors.success, const Color(0xFF22C55E));
    expect(AppRadius.homeCard, inInclusiveRange(16, 20));
    expect(AppRadius.card, 22);
    expect(AppTheme.fontFamily, 'Pretendard');
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.bg);
    expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, 'Pretendard');
    expect(AppTheme.light.textTheme.headlineMedium?.fontFamily, 'Pretendard');
  });

  testWidgets('home renewal keeps Pretendard and toss text colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('yak_home_tone_');
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
      final now = DateTime.now();
      final takenKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_08:30';
      await box.add(
        Medicine(
          name: '비타민D',
          dosage: '1알',
          times: [DoseTime(hour: 8, minute: 0)],
          memo: '',
          createdAt: now,
        ),
      );
      await box.add(
        Medicine(
          name: '유산균',
          dosage: '1포',
          times: [DoseTime(hour: 8, minute: 30)],
          memo: '',
          createdAt: now,
          takenRecords: [takenKey],
        ),
      );
    });
    addTearDown(() async {
      if (Hive.isBoxOpen(medicineBoxName)) {
        await Hive.box<Medicine>(medicineBoxName).close();
      }
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final title = tester.widget<Text>(find.text('오늘 1/2 먹었어요'));
    expect(title.style?.fontFamily, 'Pretendard');
    expect(title.style?.color, AppColors.textStrong);
    expect(title.style?.fontWeight, FontWeight.w800);
    expect(title.style?.fontSize, 24);

    final when = tester.widget<Text>(find.text('아침 8:00'));
    expect(when.style?.fontFamily, 'Pretendard');
    expect(when.style?.color, AppColors.textBody);

    final badge = tester.widget<Text>(find.text('다음 약'));
    expect(badge.style?.fontFamily, 'Pretendard');
    expect(badge.style?.color, AppColors.primaryDark);

    final dosage = tester.widget<Text>(find.text('1알'));
    expect(dosage.style?.fontFamily, 'Pretendard');
    expect(dosage.style?.color, const Color(0xFF4E5968));

    var matchedCard = false;
    final cards = find.ancestor(
      of: find.text('비타민D'),
      matching: find.byType(DecoratedBox),
    );
    for (final element in cards.evaluate()) {
      final decoration = (element.widget as DecoratedBox).decoration;
      if (decoration is! BoxDecoration) continue;
      if (decoration.borderRadius !=
          BorderRadius.circular(RenewalRadius.nowCard)) {
        continue;
      }
      expect(decoration.color, Colors.white);
      matchedCard = true;
    }
    expect(matchedCard, isTrue);
    expect(find.byIcon(Icons.block), findsNothing);
    expect(find.byTooltip('광고 제거'), findsNothing);

    final theme = Theme.of(tester.element(find.byType(HomeScreen)));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF2F4F6));
  });
}
