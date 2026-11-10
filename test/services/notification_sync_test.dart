import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

import '../support/fake_notification_center.dart';

/// 기기에 걸린 알림을 약 목록과 다시 맞춘다. (T-261110-023)
/// - 같은 시각 약은 알림 1건.
/// - 맞출 때마다 전에 걸어 둔 알림은 지우고 지금 약 목록대로만 남긴다.
Medicine med(String name, List<List<int>> times, {List<int>? weekdays}) =>
    Medicine(
      name: name,
      dosage: '1알',
      times: [for (final t in times) DoseTime(hour: t[0], minute: t[1])],
      memo: '',
      createdAt: DateTime(2026, 11, 1),
      weekdays: weekdays,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationCenter center;

  setUp(() {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
  });

  tearDown(() {
    center.uninstall();
  });

  // 이 파일의 첫 시험이어야 한다 — 아직 아무도 init 을 부르지 않은 상태.
  test('알림 준비(init) 전에는 기기 알림을 건드리지 않는다', () async {
    center.seed(0, hour: 7);

    await NotificationService.syncAll([
      med('혈압약', [
        [8, 0],
      ]),
    ]);

    expect(center.methods, isEmpty);
    expect(center.alarms, ['매일 07:00 드실 약이 있어요.']);
  });

  test('같은 시각 약 3개는 알림 1건으로 걸리고 본문에는 개수만 들어간다', () async {
    await NotificationService.init();

    await NotificationService.syncAll([
      med('혈압약', [
        [8, 0],
      ]),
      med('오메가3', [
        [8, 0],
      ]),
      med('비타민D', [
        [8, 0],
      ]),
    ]);

    expect(center.alarms, ['매일 08:00 드실 약이 3개 있어요.']);
  });

  test('약이 1개인 시각은 종전 문구 그대로 걸린다', () async {
    await NotificationService.init();

    await NotificationService.syncAll([
      med('혈압약', [
        [8, 0],
        [21, 30],
      ]),
    ]);

    expect(center.alarms, ['매일 08:00 드실 약이 있어요.', '매일 21:30 드실 약이 있어요.']);
  });

  test('요일 약은 그 요일에만 걸린다', () async {
    await NotificationService.init();

    await NotificationService.syncAll([
      med(
        '골다공증약',
        [
          [8, 0],
        ],
        weekdays: [3],
      ),
    ]);

    expect(center.alarms, ['수 08:00 드실 약이 있어요.']);
  });

  test('다시 맞추면 옛 판이 약마다 걸어 둔 알림은 사라지고 지금 약 목록대로만 남는다', () async {
    await NotificationService.init();
    center
      ..seed(0, hour: 8)
      ..seed(10, hour: 20)
      ..seed(1000, hour: 8);

    await NotificationService.syncAll([
      med('혈압약', [
        [8, 0],
      ]),
    ]);

    expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
  });

  test('약이 하나도 없으면 걸려 있던 알림을 모두 지운다', () async {
    await NotificationService.init();
    center.seed(0, hour: 8);

    await NotificationService.syncAll(const []);

    expect(center.alarms, isEmpty);
  });

  test('연달아 맞추면 마지막 약 목록이 남는다', () async {
    await NotificationService.init();

    final first = NotificationService.syncAll([
      med('A', [
        [8, 0],
      ]),
      med('B', [
        [9, 0],
      ]),
    ]);
    final second = NotificationService.syncAll([
      med('A', [
        [8, 0],
      ]),
    ]);
    await Future.wait([first, second]);

    expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
  });

  test('앱을 켤 때(initAndSync) 알림을 준비하고 약 목록대로 다시 건다', () async {
    center.seed(0, hour: 7);

    await NotificationService.initAndSync(
      () => [
        med('혈압약', [
          [8, 0],
        ]),
      ],
    );

    expect(center.methods, contains('initialize'));
    expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
  });
}
