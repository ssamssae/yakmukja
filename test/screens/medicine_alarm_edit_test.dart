import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform removing a dose time cancels its old alarm and keeps other medicines',
      (tester) async {
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('medicine_edit_alarm_'),
        ))!;
        Hive.init(dir.path);
        if (!Hive.isAdapterRegistered(0)) {
          Hive.registerAdapter(MedicineAdapter());
        }
        if (!Hive.isAdapterRegistered(1)) {
          Hive.registerAdapter(DoseTimeAdapter());
        }
        final box = (await tester.runAsync(
          () => Hive.openBox<Medicine>(medicineBoxName),
        ))!;
        final pending = <int>{};
        final rescheduled = (await tester.runAsync(
          () async => Completer<void>(),
        ))!;
        var firstMedicineSchedules = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.iOS) {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        } else {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        }
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'Asia/Seoul',
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            final args = call.arguments;
            if (call.method == 'zonedSchedule') {
              pending.add(args['id'] as int);
              if (args['id'] == 0 && ++firstMedicineSchedules == 2) {
                rescheduled.complete();
              }
            }
            if (call.method == 'cancel') {
              pending.remove(args is int ? args : args['id'] as int);
            }
            return true;
          },
        );
        try {
          await tester.runAsync(() => NotificationService.init());
          Medicine medicine(String name, List<DoseTime> times) => Medicine(
            name: name,
            dosage: '1알',
            times: times,
            memo: '',
            createdAt: DateTime(2026, 9, 26),
          );
          final first = medicine('테스트 A', [
            DoseTime(hour: 8, minute: 0),
            DoseTime(hour: 20, minute: 0),
          ]);
          final other = medicine('테스트 B', [DoseTime(hour: 9, minute: 0)]);
          await tester.runAsync(() async {
            await box.add(first);
            await box.add(other);
            await NotificationService.scheduleForMedicine(first);
            await NotificationService.scheduleForMedicine(other);
          });
          expect(pending, {0, 10, 1000});
          await tester.pumpWidget(
            MaterialApp(home: MedicineEditScreen(medicine: first)),
          );
          await tester.pumpAndSettle();
          final chip = find.widgetWithText(Chip, first.times.last.format());
          await tester.ensureVisible(chip);
          await tester.tap(
            find.descendant(
              of: chip,
              matching: find.byIcon(Icons.close_rounded),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(find.text('저장'));
            await rescheduled.future.timeout(const Duration(seconds: 5));
          });
          await tester.pumpAndSettle();
          expect(first.times.length, 1);
          expect(pending, {0, 1000});
          await tester.runAsync(() async {
            await box.close();
            final reopened = await Hive.openBox<Medicine>(medicineBoxName);
            expect(reopened.get(0)!.times.length, 1);
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await Hive.close();
            await dir.delete(recursive: true);
          });
          messenger.setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            null,
          );
          messenger.setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            null,
          );
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
