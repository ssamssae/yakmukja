import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/trash_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

import '../support/fake_notification_center.dart';

/// 휴지통에서 복원한 약은 알림도 다시 걸린다. (T-261110-023)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform: 휴지통에서 복원하면 그 약의 알림이 다시 걸린다', (tester) async {
      tester.view.physicalSize = const Size(402, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      NotificationService.resetForTest();
      final center = FakeNotificationCenter()..install(platform);
      late Directory dir;
      late Box<Medicine> box;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('yak_trash_alarm_');
        Hive.init(dir.path);
        if (!Hive.isAdapterRegistered(0)) {
          Hive.registerAdapter(MedicineAdapter());
        }
        if (!Hive.isAdapterRegistered(1)) {
          Hive.registerAdapter(DoseTimeAdapter());
        }
        box = await Hive.openBox<Medicine>(medicineBoxName);
        await box.add(
          Medicine(
            name: '혈압약',
            dosage: '1알',
            times: [DoseTime(hour: 9, minute: 0)],
            memo: '',
            createdAt: DateTime(2026, 10, 1),
          ),
        );
        await box.add(
          Medicine(
            name: '오메가3',
            dosage: '1알',
            times: [DoseTime(hour: 8, minute: 0)],
            memo: '',
            createdAt: DateTime(2026, 10, 1),
            deletedAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        );
        await NotificationService.init();
        await NotificationService.syncAll(box.values);
      });
      try {
        expect(center.alarms, ['매일 09:00 드실 약이 있어요.']);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: const TrashScreen()),
        );
        await tester.pump();
        final restore = find.text('복원').first;
        await tester.ensureVisible(restore);
        final ink = tester.widget<InkWell>(
          find.ancestor(of: restore, matching: find.byType(InkWell)).first,
        );
        await tester.runAsync(() async {
          ink.onTap!.call();
          // 최대 3초 기다린다. 끝내 안 걸리면 그 자리에서 실패한다.
          for (var i = 0; center.alarms.length != 2; i++) {
            if (i == 300) fail('3초 안에 알림이 2건이 되지 않았다');
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump();

        expect(center.alarms, ['매일 08:00 드실 약이 있어요.', '매일 09:00 드실 약이 있어요.']);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await Hive.close();
          await dir.delete(recursive: true);
        });
        center.uninstall();
      }
    });
  }
}
