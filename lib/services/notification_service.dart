import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
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
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// 약에 등록된 모든 시간에 매일 반복 알림 스케줄
  static Future<void> scheduleForMedicine(Medicine medicine) async {
    await cancelForMedicine(medicine);

    for (int i = 0; i < medicine.times.length; i++) {
      final t = medicine.times[i];
      final id = _notificationId(medicine, i);

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
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  static Future<void> cancelForMedicine(Medicine medicine) async {
    for (int i = 0; i < medicine.times.length; i++) {
      await _plugin.cancel(id: _notificationId(medicine, i));
    }
  }

  static int _notificationId(Medicine medicine, int timeIndex) {
    return (medicine.key as int) * 100 + timeIndex;
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
