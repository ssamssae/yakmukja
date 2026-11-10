import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

import '../support/fake_notification_center.dart';

/// 끝나는 날이 있는 약의 알림을 기기에 건다. (T-261110-042)
Medicine med(String name, List<List<int>> times, {DateTime? endDate}) =>
    Medicine(
      name: name,
      dosage: '1알',
      times: [for (final t in times) DoseTime(hour: t[0], minute: t[1])],
      memo: '',
      createdAt: DateTime(2026, 11, 1),
      endDate: endDate,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationCenter center;

  // 알림 계획의 「지금」. 한 번 울리는 알림은 실제 시계보다 뒤여야 기기가 받아 주므로
  // 먼 앞날로 둔다.
  late DateTime now;

  setUp(() {
    NotificationService.resetForTest();
    now = DateTime(2099, 1, 5, 7, 0);
    NotificationService.clock = () => now;
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
  });

  tearDown(() {
    center.uninstall();
    NotificationService.resetForTest();
  });

  test('끝나는 약은 남은 날짜마다 한 번 울리는 알림으로 걸린다', () async {
    await NotificationService.init();

    await NotificationService.syncAll([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2099, 1, 7)),
    ]);

    expect(center.onceAlarms, [
      '2099-01-05 08:00 드실 약이 있어요.',
      '2099-01-06 08:00 드실 약이 있어요.',
      '2099-01-07 08:00 드실 약이 있어요.',
    ]);
    expect(center.pending, hasLength(3));
  });

  test('계속 먹는 약과 같은 시각이면 되풀이 알림 1건만 걸리고 개수는 말하지 않는다', () async {
    await NotificationService.init();

    await NotificationService.syncAll([
      med('혈압약', [
        [8, 0],
      ]),
      med('비타민', [
        [8, 0],
      ]),
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2099, 1, 7)),
    ]);

    expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
  });

  test('다시 맞추면 지나간 날짜의 알림은 없어지고 남은 날짜만 걸린다', () async {
    await NotificationService.init();
    final medicines = [
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2099, 1, 7)),
    ];
    await NotificationService.syncAll(medicines);

    now = DateTime(2099, 1, 6, 9, 0);
    await NotificationService.syncAll(medicines);

    expect(center.onceAlarms, ['2099-01-07 08:00 드실 약이 있어요.']);
  });

  test('끝나는 날이 지난 뒤 맞추면 그 약의 알림은 하나도 없다', () async {
    await NotificationService.init();
    final medicines = [
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2099, 1, 7)),
    ];
    await NotificationService.syncAll(medicines);

    now = DateTime(2099, 1, 8, 7, 0);
    await NotificationService.syncAll(medicines);

    expect(center.pending, isEmpty);
  });

  test('한 번 울리는 알림 하나가 실패해도 나머지는 걸린다', () async {
    await NotificationService.init();
    final plan = NotificationService.planSlots([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2099, 1, 7)),
    ], now: now);
    center.failScheduleIds.add(plan[1].id);

    await NotificationService.syncAll([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2099, 1, 7)),
    ]);

    expect(center.onceAlarms, [
      '2099-01-05 08:00 드실 약이 있어요.',
      '2099-01-07 08:00 드실 약이 있어요.',
    ]);
  });

  group('날이 바뀐 뒤 다시 맞추기', () {
    final medicines = [
      med('혈압약', [
        [8, 0],
      ]),
      med('항생제', [
        [21, 0],
      ], endDate: DateTime(2099, 1, 6)),
    ];

    test('같은 날에는 다시 맞추지 않는다', () async {
      await NotificationService.initAndSync(() => medicines);
      center.methods.clear();

      await NotificationService.resyncIfNewDay();

      expect(center.methods, isEmpty);
    });

    test('날이 바뀌었으면 다시 맞춘다 — 끝난 약의 알림이 빠진다', () async {
      await NotificationService.initAndSync(() => medicines);
      expect(center.onceAlarms, [
        '2099-01-05 21:00 드실 약이 있어요.',
        '2099-01-06 21:00 드실 약이 있어요.',
      ]);

      now = DateTime(2099, 1, 7, 7, 0);
      await NotificationService.resyncIfNewDay();

      expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
    });

    test('날이 바뀌었으면 기기가 잃어버린 알림도 다시 걸린다', () async {
      await NotificationService.initAndSync(() => medicines);
      center.pending.clear();

      now = DateTime(2099, 1, 6, 7, 0);
      await NotificationService.resyncIfNewDay();

      expect(center.alarms, ['매일 08:00 드실 약이 있어요.', '한 번 화 21:00 드실 약이 있어요.']);
    });

    test('앱을 켤 때 약 목록을 받은 적이 없으면 아무것도 하지 않는다', () async {
      await NotificationService.resyncIfNewDay();

      expect(center.methods, isEmpty);
    });
  });
}
