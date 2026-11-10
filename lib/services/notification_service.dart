import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';

/// 한 시각에 울릴 알림 1건. 같은 시각에 먹는 약은 한 건으로 묶는다. (T-261110-023)
class DoseSlot {
  const DoseSlot({
    required this.hour,
    required this.minute,
    required this.weekday,
    required this.count,
  });

  final int hour;
  final int minute;

  /// 0 = 매일, 1..7 = 그 ISO 요일(월~일)에만.
  final int weekday;

  /// 이 시각에 먹을 약 개수.
  final int count;

  /// 알림 id — (시각 × 요일칸)마다 하나. 900000 + 하루 중 분 × 10 + 요일칸.
  int get id => 900000 + (hour * 60 + minute) * 10 + weekday;

  /// 잠금화면에 약 이름·복용량이 드러나지 않게 개수만 알린다.
  String get body => count == 1 ? '드실 약이 있어요.' : '드실 약이 $count개 있어요.';
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void>? _initFuture;

  /// 알림을 준비한다(시간대·권한). 진행 중인 준비는 [syncAll] 이 기다린다.
  static Future<void> init() {
    final future = _init();
    _initFuture = future;
    return future;
  }

  /// 앱을 켤 때: 알림을 준비하고, 기기에 걸린 알림을 지금 약 목록과 다시 맞춘다.
  /// 예약이 빠졌거나 기기에서 사라졌어도 여기서 스스로 복구된다. (T-261110-023)
  static Future<void> initAndSync(
    Iterable<Medicine> Function() medicines,
  ) async {
    await init();
    await syncAll(medicines());
  }

  static Future<void> _init() async {
    try {
      tz.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await _plugin.initialize(
        settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
      );

      // iOS 권한 요청
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      // Android 권한 요청
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      // Android 12+ 정확한 알람 권한 — 없으면 Doze 에서 지정시각이 지연됨
      await android?.requestExactAlarmsPermission();

      _initialized = true;
    } catch (e, st) {
      debugPrint('[NotificationService.init] failed: $e\n$st');
      _initialized = false;
    }
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'medicine_reminder',
      '복용 알림',
      channelDescription: '약 복용 시간 알림',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  /// 약 목록 → 울려야 할 알림. 같은 시각에 먹는 약은 1건으로 묶는다.
  /// - 그 시각에 먹을 약 개수가 일주일 내내 같으면 매일 알림 1건.
  /// - 요일마다 다르면 약이 있는 요일마다 1건.
  /// 휴지통 약은 뺀다.
  static List<DoseSlot> planSlots(Iterable<Medicine> medicines) {
    // 하루 중 분 → 요일(월~일)별 약 개수.
    final countsByTime = <int, List<int>>{};
    for (final medicine in medicines) {
      if (medicine.deletedAt != null) continue;
      final minutes = {for (final t in medicine.times) t.hour * 60 + t.minute};
      final weekdays = {...medicine.activeWeekdays};
      for (final minuteOfDay in minutes) {
        final counts = countsByTime.putIfAbsent(
          minuteOfDay,
          () => List.filled(7, 0),
        );
        for (final weekday in weekdays) {
          if (weekday >= 1 && weekday <= 7) counts[weekday - 1]++;
        }
      }
    }

    final slots = <DoseSlot>[];
    for (final minuteOfDay in countsByTime.keys.toList()..sort()) {
      final counts = countsByTime[minuteOfDay]!;
      final hour = minuteOfDay ~/ 60;
      final minute = minuteOfDay % 60;
      if (counts.every((count) => count == counts.first)) {
        if (counts.first > 0) {
          slots.add(
            DoseSlot(
              hour: hour,
              minute: minute,
              weekday: 0,
              count: counts.first,
            ),
          );
        }
        continue;
      }
      for (var weekday = 1; weekday <= 7; weekday++) {
        final count = counts[weekday - 1];
        if (count == 0) continue;
        slots.add(
          DoseSlot(hour: hour, minute: minute, weekday: weekday, count: count),
        );
      }
    }
    return slots;
  }

  static Future<void> _syncTail = Future<void>.value();
  static int _syncGeneration = 0;

  /// 기기에 걸린 알림을 약 목록과 다시 맞춘다. (T-261110-023)
  /// - 전에 걸어 둔 알림(옛 판이 약마다 걸어 둔 것 포함)은 지우고 지금 계획대로만 남긴다.
  /// - 알림 준비([init])가 진행 중이면 기다린다. 준비한 적이 없거나 실패했으면 건너뛴다
  ///   (다음에 앱을 켤 때 [initAndSync] 가 다시 맞춘다).
  /// - 연달아 부르면 마지막 약 목록이 남는다. 실패해도 예외를 던지지 않는다.
  static Future<void> syncAll(Iterable<Medicine> medicines) {
    final plan = planSlots(medicines);
    final generation = ++_syncGeneration;
    return _syncTail = _syncTail.then((_) async {
      // 더 새 요청이 뒤에 줄 서 있으면 그쪽이 맞춘다.
      if (generation != _syncGeneration) return;
      await _applyIfReady(plan);
    });
  }

  static Future<void> _applyIfReady(List<DoseSlot> plan) async {
    final ready = _initFuture;
    if (ready == null) return;
    await ready;
    if (!_initialized) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final slot in plan) {
        final daily = slot.weekday == 0;
        await _plugin.zonedSchedule(
          id: slot.id,
          title: '약먹자 💊',
          body: slot.body,
          scheduledDate: daily
              ? _nextDateTime(slot.hour, slot.minute)
              : _nextDateTimeOnWeekday(slot.weekday, slot.hour, slot.minute),
          notificationDetails: _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: daily
              ? DateTimeComponents.time
              : DateTimeComponents.dayOfWeekAndTime,
        );
      }
    } catch (e, st) {
      debugPrint('[NotificationService.syncAll] failed: $e\n$st');
    }
  }

  /// 다음 해당 ISO 요일(1=월 … 7=일)의 지정 시:분 (현재 이후).
  static tz.TZDateTime _nextDateTimeOnWeekday(int isoWeekday, int hour, int minute) {
    var scheduled = _nextDateTime(hour, minute);
    // _nextDateTime 은 오늘/내일의 시:분만 맞춤 — 요일까지 전진.
    while (scheduled.weekday != isoWeekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static tz.TZDateTime _nextDateTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  // 테스트 전용 접근자 — 순수 계산 로직(다음 알림 시각)을 단위 테스트로 검증.
  // 동작/디자인 변경 없음(기존 private 로직을 그대로 위임).
  @visibleForTesting
  static tz.TZDateTime nextDateTimeForTest(int hour, int minute) =>
      _nextDateTime(hour, minute);

  @visibleForTesting
  static tz.TZDateTime nextDateTimeOnWeekdayForTest(
          int isoWeekday, int hour, int minute) =>
      _nextDateTimeOnWeekday(isoWeekday, hour, minute);
}
