import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/services/notification_service.dart';

import '../support/fake_notification_center.dart';

/// 약을 고치거나 지우면 기기에 걸린 알림도 약 목록대로 바뀐다.
/// (T-260926-017 복용 시간 삭제 · T-261110-023 시각별 알림 다시 맞추기)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Medicine medicine(String name, List<DoseTime> times) => Medicine(
    name: name,
    dosage: '1알',
    times: times,
    memo: '',
    createdAt: DateTime(2026, 9, 26),
  );

  /// 진짜 시간에서 조건이 될 때까지 최대 3초 기다린다. 끝내 안 되면 그 자리에서 실패한다.
  Future<void> waitFor(bool Function() done, String what) async {
    for (var i = 0; i < 300; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('3초 안에 되지 않았다: $what');
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('$platform', () {
      late FakeNotificationCenter center;
      late Directory dir;
      late Box<Medicine> box;
      late Medicine first;
      late Medicine other;

      Future<void> open(WidgetTester tester) async {
        NotificationService.resetForTest();
        center = FakeNotificationCenter()..install(platform);
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('medicine_edit_alarm_');
          Hive.init(dir.path);
          if (!Hive.isAdapterRegistered(0)) {
            Hive.registerAdapter(MedicineAdapter());
          }
          if (!Hive.isAdapterRegistered(1)) {
            Hive.registerAdapter(DoseTimeAdapter());
          }
          box = await Hive.openBox<Medicine>(medicineBoxName);
          first = medicine('테스트 A', [
            DoseTime(hour: 8, minute: 0),
            DoseTime(hour: 20, minute: 0),
          ]);
          other = medicine('테스트 B', [DoseTime(hour: 9, minute: 0)]);
          await box.add(first);
          await box.add(other);
          await NotificationService.init();
          await NotificationService.syncAll(box.values);
        });
      }

      Future<void> close(WidgetTester tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await Hive.close();
          await dir.delete(recursive: true);
        });
        center.uninstall();
      }

      testWidgets('복용 시간을 지우고 저장하면 그 시각 알림만 사라지고 다른 약 알림은 남는다', (tester) async {
        await open(tester);
        try {
          expect(center.alarms, [
            '매일 08:00 드실 약이 있어요.',
            '매일 09:00 드실 약이 있어요.',
            '매일 20:00 드실 약이 있어요.',
          ]);

          await tester.pumpWidget(
            MaterialApp(home: MedicineEditScreen(medicine: first)),
          );
          await tester.pumpAndSettle();
          final chip = find.widgetWithText(Chip, '저녁 8:00');
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
            await waitFor(() => center.alarms.length == 2, '알림 2건으로 줄기');
          });
          await tester.pumpAndSettle();

          expect(first.times.length, 1);
          expect(center.alarms, ['매일 08:00 드실 약이 있어요.', '매일 09:00 드실 약이 있어요.']);
          await tester.runAsync(() async {
            await box.close();
            final reopened = await Hive.openBox<Medicine>(medicineBoxName);
            expect(reopened.get(0)!.times.length, 1);
          });
        } finally {
          await close(tester);
        }
      });

      testWidgets('약을 삭제(휴지통)하면 그 약의 알림이 사라지고 다른 약 알림은 남는다', (tester) async {
        await open(tester);
        try {
          await tester.pumpWidget(
            MaterialApp(home: MedicineEditScreen(medicine: first)),
          );
          await tester.pumpAndSettle();
          // 삭제는 디스크 저장을 기다린다. 그 함수를 가짜 시간에서 시작하면 상자
          // 닫기와 서로 기다리므로, 단추 콜백은 진짜 시간에서 시작하고 확인 창
          // 탭만 시험 시간에서 한다.
          final deleteButton = tester.widget<TextButton>(
            find.widgetWithText(TextButton, '삭제'),
          );
          await tester.runAsync(() async {
            deleteButton.onPressed!.call();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.widgetWithText(FilledButton, '삭제'));
          await tester.runAsync(
            () => waitFor(() => center.alarms.length == 1, '알림 1건으로 줄기'),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(first.isInTrash, isTrue);
          expect(center.alarms, ['매일 09:00 드실 약이 있어요.']);
        } finally {
          await close(tester);
        }
      });

      testWidgets('알림 맞추기가 끝나지 않아도 저장하면 화면이 닫힌다', (tester) async {
        await open(tester);
        final stuck = Completer<void>();
        try {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: Text('바닥 화면'))),
          );
          unawaited(
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => MedicineEditScreen(medicine: other),
                  ),
                ),
          );
          await tester.pumpAndSettle();
          // 기기가 알림 요청에 답하지 않는다.
          center.hold = stuck.future;
          final callsBefore = center.methods.length;

          await tester.runAsync(() async {
            await tester.tap(find.text('저장'));
            await waitFor(
              () => center.methods.length > callsBefore,
              '알림 맞추기 시작',
            );
          });
          await tester.pumpAndSettle();

          expect(find.byType(MedicineEditScreen), findsNothing);
          expect(find.text('바닥 화면'), findsOneWidget);
        } finally {
          stuck.complete();
          await close(tester);
        }
      });
    });
  }
}
