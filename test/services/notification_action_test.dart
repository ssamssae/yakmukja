import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

import '../support/fake_notification_center.dart';

/// 알림의 「먹었어요」·「10분 뒤 다시」. 단추를 누르면 앱이 열리고, 기록은 본
/// isolate 의 Hive 에만 남긴다. (T-261110-045)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationCenter center;
  late Box<Medicine> box;

  final day = DateTime(2099, 6, 15);
  DateTime at(int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  String record(int hour, int minute) => Medicine.recordKey(day, hour, minute);

  Medicine med(
    String name,
    int hour,
    int minute, {
    List<int>? weekdays,
    DateTime? endDate,
    DateTime? deletedAt,
    List<String>? takenRecords,
  }) => Medicine(
    name: name,
    dosage: '1알',
    times: [DoseTime(hour: hour, minute: minute)],
    memo: '',
    createdAt: DateTime(2026, 11, 1),
    weekdays: weekdays,
    endDate: endDate,
    deletedAt: deletedAt,
    takenRecords: takenRecords,
  );

  setUpAll(() async {
    Hive.init(Directory.systemTemp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  setUp(() async {
    NotificationService.resetForTest();
    await box.clear();
    center = FakeNotificationCenter();
  });

  tearDown(() {
    center.uninstall();
    NotificationService.resetForTest();
  });

  tearDownAll(() async {
    await box.close();
  });

  Future<void> boot(TargetPlatform platform, DateTime now) async {
    center = FakeNotificationCenter()..install(platform);
    NotificationService.clock = () => now;
    await NotificationService.initAndSync(() => box.values);
  }

  Map<String, Object?> launch({
    required String actionId,
    required String payload,
  }) => <String, Object?>{
    'notificationId': 1,
    'actionId': actionId,
    'input': '',
    'payload': payload,
    'notificationResponseType': 1,
  };

  test('iOS 카테고리 dose_v1 의 두 단추는 앱을 여는 foreground 옵션이다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    await NotificationService.init();

    final categories =
        center.initializeArgs?['notificationCategories'] as List<dynamic>;
    expect(categories, hasLength(1));
    final category = categories.single as Map;
    expect(category['identifier'], 'dose_v1');
    final actions = category['actions'] as List<dynamic>;
    expect(actions, hasLength(2));
    expect((actions[0] as Map)['identifier'], 'take');
    expect((actions[0] as Map)['title'], '먹었어요');
    expect((actions[1] as Map)['identifier'], 'snooze10');
    expect((actions[1] as Map)['title'], '10분 뒤 다시');
    // foreground = 1 << 2. 백그라운드 처리 옵션은 넣지 않는다.
    for (final action in actions) {
      expect((action as Map)['options'], [4]);
    }
    expect(center.initializeArgs?.containsKey('dispatcher_handle'), isFalse);
    expect(center.initializeArgs?.containsKey('callback_handle'), isFalse);
  });

  test('안드로이드 두 단추는 앱을 연다', () async {
    await box.add(med('혈압약', 8, 0));
    await boot(TargetPlatform.android, at(9, 0));

    final alarm = center.pending.values.single;
    final actions = alarm.platformSpecifics?['actions'] as List<dynamic>;
    expect(actions, hasLength(2));
    expect((actions[0] as Map)['id'], 'take');
    expect((actions[0] as Map)['title'], '먹었어요');
    expect((actions[1] as Map)['id'], 'snooze10');
    expect((actions[1] as Map)['title'], '10분 뒤 다시');
    for (final action in actions) {
      expect((action as Map)['showsUserInterface'], isTrue);
    }
    expect(center.initializeArgs?.containsKey('dispatcher_handle'), isFalse);
  });

  test('되풀이 알림과 끝나는 날의 1회 알림은 같은 payload·단추를 달고 id 는 2^27 미만이다', () async {
    await box.add(med('혈압약', 8, 0));
    await box.add(med('항생제', 21, 30, endDate: DateTime(2099, 6, 16)));
    await boot(TargetPlatform.iOS, at(7, 0));

    expect(center.pending, isNotEmpty);
    for (final entry in center.pending.entries) {
      expect(entry.key, lessThan(1 << 27));
      expect(entry.value.payload, startsWith('dose:'));
      expect(entry.value.platformSpecifics?['categoryIdentifier'], 'dose_v1');
    }
    final daily = center.pending.values.singleWhere((alarm) => !alarm.once);
    final once = center.pending.values.where((alarm) => alarm.once);
    expect(daily.payload, 'dose:08:00');
    expect(daily.body, '드실 약이 있어요.');
    expect(once, isNotEmpty);
    for (final alarm in once) {
      expect(alarm.payload, 'dose:21:30');
      expect(alarm.body, '드실 약이 있어요.');
    }

    final repeatMax = const DoseSlot(
      hour: 23,
      minute: 59,
      weekday: 7,
      count: 1,
    ).id;
    final onceMax = DoseSlot(
      hour: 23,
      minute: 59,
      weekday: 1,
      count: 1,
      date: DateTime(2099, 12, 31),
    ).id;
    expect(repeatMax, lessThan(1 << 27));
    expect(onceMax, lessThan(1 << 27));
    expect(800000 + 23 * 60 + 59, lessThan(1 << 27));
  });

  test('대기 알림 상한 60에 다시 알림 1건을 더해도 iOS 64건을 넘지 않는다', () {
    final medicines = [
      for (var hour = 0; hour < 24; hour++)
        med('약$hour', hour, 0, endDate: DateTime(2099, 6, 20)),
    ];
    final slots = NotificationService.planSlots(medicines, now: at(0, 0));
    expect(slots.length, 60);
    expect(slots.length + 1, lessThanOrEqualTo(64));
  });

  test('앱이 떠 있을 때 「먹었어요」는 오늘 그 시각의 안 먹은 약만 먹음으로 남긴다', () async {
    final offWeekday = day.weekday == 7 ? 1 : day.weekday + 1;
    await box.add(med('혈압약', 8, 0));
    await box.add(med('비타민', 8, 0, takenRecords: [record(8, 0)]));
    await box.add(med('저녁약', 21, 0));
    await box.add(med('휴지통', 8, 0, deletedAt: DateTime(2099, 6, 1)));
    await box.add(med('다른요일', 8, 0, weekdays: [offWeekday]));
    await box.add(med('끝난약', 8, 0, endDate: DateTime(2099, 6, 14)));
    await boot(TargetPlatform.iOS, at(9, 30));

    await center.deliverResponse(
      notificationResponseType: 1,
      actionId: 'take',
      payload: 'dose:08:00',
    );
    await NotificationService.settleForTest();

    Medicine named(String name) => box.values.firstWhere((m) => m.name == name);
    expect(named('혈압약').takenRecords, [record(8, 0)]);
    expect(named('비타민').takenRecords, [record(8, 0)]);
    expect(named('저녁약').takenRecords, isEmpty);
    expect(named('휴지통').takenRecords, isEmpty);
    expect(named('다른요일').takenRecords, isEmpty);
    expect(named('끝난약').takenRecords, isEmpty);
  });

  test('알림 본문을 눌러도 약을 먹음으로 남기지 않는다', () async {
    await box.add(med('혈압약', 8, 0));
    await boot(TargetPlatform.android, at(9, 30));

    await center.deliverResponse(
      notificationResponseType: 0,
      payload: 'dose:08:00',
    );
    await NotificationService.settleForTest();

    expect(box.values.single.takenRecords, isEmpty);
  });

  test('앱이 꺼진 상태에서 「먹었어요」로 켜지면 시작할 때 처리한다', () async {
    await box.add(med('혈압약', 8, 0));
    await box.add(med('비타민', 8, 0));
    center = FakeNotificationCenter()
      ..install(TargetPlatform.android)
      ..launchResponse = launch(actionId: 'take', payload: 'dose:08:00');
    NotificationService.clock = () => at(9, 30);

    await NotificationService.initAndSync(() => box.values);

    expect(box.values.map((m) => m.takenRecords), everyElement([record(8, 0)]));
  });

  test('지금 시각이 약 시각보다 이르면 지난 날 알림이라 무시한다', () async {
    await box.add(med('혈압약', 8, 0));
    await boot(TargetPlatform.iOS, at(7, 0));

    await center.deliverResponse(
      notificationResponseType: 1,
      actionId: 'take',
      payload: 'dose:08:00',
    );
    await NotificationService.settleForTest();

    expect(box.values.single.takenRecords, isEmpty);
  });

  test('꺼진 앱을 이른 시각의 지난 알림으로 켜도 무시한다', () async {
    await box.add(med('혈압약', 8, 0));
    center = FakeNotificationCenter()
      ..install(TargetPlatform.iOS)
      ..launchResponse = launch(actionId: 'take', payload: 'dose:08:00');
    NotificationService.clock = () => at(7, 59);

    await NotificationService.initAndSync(() => box.values);

    expect(box.values.single.takenRecords, isEmpty);
  });

  test('「10분 뒤 다시」는 1회 알림이고 맞춘 뒤에도 남으며 지난 것은 버린다', () async {
    await box.add(med('혈압약', 8, 0));
    await box.add(med('비타민', 8, 0));
    await box.add(med('오메가', 8, 0));
    var now = at(8, 0);
    await boot(TargetPlatform.iOS, now);
    NotificationService.clock = () => now;

    await center.deliverResponse(
      notificationResponseType: 1,
      actionId: 'snooze10',
      payload: 'dose:08:00',
    );
    await NotificationService.settleForTest();

    const snoozeId = 800000 + 8 * 60 + 10;
    FakeAlarm snooze() => center.pending[snoozeId]!;
    expect(center.pending.containsKey(snoozeId), isTrue);
    expect(snooze().once, isTrue);
    expect(snooze().payload, 'dose:08:00');
    expect(snooze().body, '드실 약이 3개 있어요.');
    expect(snooze().at, at(8, 10));
    expect(snooze().platformSpecifics?['categoryIdentifier'], 'dose_v1');
    expect(snoozeId, lessThan(1 << 27));

    await NotificationService.syncAll(box.values);
    expect(center.pending.containsKey(snoozeId), isTrue);
    expect(snooze().once, isTrue);
    expect(snooze().payload, 'dose:08:00');
    expect(snooze().body, '드실 약이 3개 있어요.');
    expect(center.pending.values.where((alarm) => !alarm.once), isNotEmpty);

    now = at(8, 11);
    await NotificationService.syncAll(box.values);
    expect(center.pending.containsKey(snoozeId), isFalse);
    expect(center.alarms, ['매일 08:00 드실 약이 3개 있어요.']);

    now = at(8, 0);
    await NotificationService.syncAll(box.values);
    expect(center.pending.containsKey(snoozeId), isFalse);
  });

  test('꺼진 앱을 「10분 뒤 다시」로 켜도 시작할 때 1회 알림이 남는다', () async {
    await box.add(med('혈압약', 8, 0));
    center = FakeNotificationCenter()
      ..install(TargetPlatform.android)
      ..launchResponse = launch(actionId: 'snooze10', payload: 'dose:08:00');
    NotificationService.clock = () => at(8, 0);

    await NotificationService.initAndSync(() => box.values);

    const snoozeId = 800000 + 8 * 60 + 10;
    final snooze = center.pending[snoozeId];
    expect(snooze, isNotNull);
    expect(snooze!.once, isTrue);
    expect(snooze.payload, 'dose:08:00');
    expect(snooze.body, '드실 약이 있어요.');
    final actions = snooze.platformSpecifics?['actions'] as List<dynamic>;
    for (final action in actions) {
      expect((action as Map)['showsUserInterface'], isTrue);
    }
  });
}
