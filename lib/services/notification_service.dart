import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
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

  /// 약에 등록된 시간 × 선택 요일에 반복 알림 스케줄.
  /// - 매일(7요일 전부) 약은 시간마다 1개(DateTimeComponents.time)로 효율 유지.
  /// - 특정 요일만 선택한 약은 (시간 × 요일) 조합마다 dayOfWeekAndTime 으로 예약.
  static Future<void> scheduleForMedicine(Medicine medicine) async {
    if (!_initialized) return;
    await cancelForMedicine(medicine);

    final daily = medicine.isDaily;

    for (int i = 0; i < medicine.times.length; i++) {
      final t = medicine.times[i];

      if (daily) {
        final id = _notificationId(medicine, i, 0);
        if (id == null) continue;
        // 잠금화면에 약 이름·복용량 평문 노출 방지. 자세한 내용은 앱 진입 후만.
        await _plugin.zonedSchedule(
          id: id,
          title: '약먹자 💊',
          body: '드실 약이 있어요.',
          scheduledDate: _nextDateTime(t.hour, t.minute),
          notificationDetails: _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        for (final wd in medicine.activeWeekdays) {
          final id = _notificationId(medicine, i, wd);
          if (id == null) continue;
          await _plugin.zonedSchedule(
            id: id,
            title: '약먹자 💊',
            body: '드실 약이 있어요.',
            scheduledDate: _nextDateTimeOnWeekday(wd, t.hour, t.minute),
            notificationDetails: _notificationDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
    }
  }

  static Future<void> cancelForMedicine(Medicine medicine) async {
    if (!_initialized) return;
    // key 가 null 화(=삭제) 되기 전에 id 를 먼저 스냅샷 — 호출자가 await 안 하고
    // 곧바로 medicine.delete() 를 돌려도 취소 대상을 놓치지 않는다.
    // 요일 변경 후 재스케줄 시 잔여 알림이 안 남도록, 시간마다 daily 슬롯(0) +
    // 전체 요일 슬롯(1..7)을 모두 취소한다.
    final ids = <int>{};
    for (int i = 0; i < medicine.times.length; i++) {
      for (int wd = 0; wd <= 7; wd++) {
        final id = _notificationId(medicine, i, wd);
        if (id != null) ids.add(id);
      }
      // 구버전 id 스킴(key*100+timeIndex)으로 예약된 알림도 함께 취소(업그레이드 호환).
      final legacy = _legacyNotificationId(medicine, i);
      if (legacy != null) ids.add(legacy);
    }
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  /// Box 에 아직 저장 전이면 key 가 null — 그 경우 null 반환해 schedule 생략.
  /// id = key*1000 + timeIndex*10 + weekdaySlot.
  /// weekdaySlot: 0=매일(time 매칭), 1..7=특정 ISO 요일(dayOfWeekAndTime 매칭).
  static int? _notificationId(Medicine medicine, int timeIndex, int weekdaySlot) {
    final key = medicine.key;
    if (key is! int) return null;
    return key * 1000 + timeIndex * 10 + weekdaySlot;
  }

  /// 구버전(요일 도입 전) id 스킴. 업그레이드 시 잔여 알림 취소용.
  static int? _legacyNotificationId(Medicine medicine, int timeIndex) {
    final key = medicine.key;
    if (key is! int) return null;
    return key * 100 + timeIndex;
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

  // 테스트 전용 접근자 — 순수 계산 로직(다음 알림 시각·알림 id)을 단위 테스트로 검증.
  // 동작/디자인 변경 없음(기존 private 로직을 그대로 위임).
  @visibleForTesting
  static tz.TZDateTime nextDateTimeForTest(int hour, int minute) =>
      _nextDateTime(hour, minute);

  @visibleForTesting
  static int? notificationIdForTest(Medicine medicine, int timeIndex,
          [int weekdaySlot = 0]) =>
      _notificationId(medicine, timeIndex, weekdaySlot);

  @visibleForTesting
  static tz.TZDateTime nextDateTimeOnWeekdayForTest(
          int isoWeekday, int hour, int minute) =>
      _nextDateTimeOnWeekday(isoWeekday, hour, minute);
}
