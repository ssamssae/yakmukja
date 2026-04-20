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

  /// 약에 등록된 모든 시간에 매일 반복 알림 스케줄
  static Future<void> scheduleForMedicine(Medicine medicine) async {
    if (!_initialized) return;
    await cancelForMedicine(medicine);

    for (int i = 0; i < medicine.times.length; i++) {
      final t = medicine.times[i];
      final id = _notificationId(medicine, i);
      if (id == null) continue;

      await _plugin.zonedSchedule(
        id: id,
        title: '약먹자 💊',
        body: '${medicine.name} ${medicine.dosage} 드실 시간입니다.',
        scheduledDate: _nextDateTime(t.hour, t.minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'medicine_reminder',
            '복용 알림',
            channelDescription: '약 복용 시간 알림',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  static Future<void> cancelForMedicine(Medicine medicine) async {
    if (!_initialized) return;
    // key 가 null 화(=삭제) 되기 전에 id 를 먼저 스냅샷 — 호출자가 await 안 하고
    // 곧바로 medicine.delete() 를 돌려도 취소 대상을 놓치지 않는다.
    final ids = <int>[];
    for (int i = 0; i < medicine.times.length; i++) {
      final id = _notificationId(medicine, i);
      if (id != null) ids.add(id);
    }
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  /// Box 에 아직 저장 전이면 key 가 null — 그 경우 null 반환해 schedule 생략.
  static int? _notificationId(Medicine medicine, int timeIndex) {
    final key = medicine.key;
    if (key is! int) return null;
    return key * 100 + timeIndex;
  }

  static tz.TZDateTime _nextDateTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
