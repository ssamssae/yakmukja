import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

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

/// 「알림 켜기」를 눌렀을 때의 결과. (T-261110-026)
enum NotificationEnableResult {
  /// 권한을 받았다. 알림이 켜졌다.
  granted,

  /// 앱에서는 더 물을 수 없어 기기의 앱 설정 화면을 열었다(iOS).
  openedSettings,

  /// 앱에서 켤 수 없다. 기기 설정에서 직접 켜야 한다.
  needsManual,
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// 기기에서 이 앱의 알림이 켜져 있는지. null = 아직 모른다(알림 준비 전, 또는 한 번도
  /// 읽지 못함). 읽기에 실패하면 마지막으로 읽은 값을 그대로 둔다.
  /// 꺼져 있으면 홈이 안내를 띄운다. (T-261110-026)
  static final ValueNotifier<bool?> enabled = ValueNotifier<bool?>(null);

  /// 앱을 켤 때 받은 약 목록. 알림이 켜진 것을 알게 되면 이걸로 다시 맞춘다.
  static Iterable<Medicine> Function()? _medicines;
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
    _medicines = medicines;
    await init();
    await syncAll(medicines());
  }

  /// 기기 설정의 알림 권한을 다시 읽는다. 앱이 다시 앞으로 올 때 부른다.
  /// 꺼져 있다가 켜진 것을 알게 되면 약 목록대로 알림을 다시 건다 —
  /// iOS 는 권한이 없는 동안 예약 자체가 실패하기 때문이다. (T-261110-026)
  static Future<void> refreshPermission() async {
    // 알림 준비를 한 적이 없거나(스토어 화면 캡처 모드) 실패했으면 권한 상태를 말하지
    // 않는다 — 알림을 걸 수 없는 채로 「꺼짐→켜짐」을 말하면 화면만 괜찮다고 한다.
    final ready = _initFuture;
    if (ready == null) return;
    await ready;
    if (!_initialized) return;
    final before = enabled.value;
    await _readPermission();
    // 켜져 있는 것을 새로 알게 됐다(꺼짐→켜짐, 모름→켜짐).
    if (before != true && enabled.value == true) {
      final medicines = _medicines;
      if (medicines != null) await syncAll(medicines());
    }
  }

  static Future<void> _readPermission() async {
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        enabled.value = (await ios.checkPermissions())?.isEnabled;
        return;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        enabled.value = await android.areNotificationsEnabled();
      }
    } catch (e, st) {
      debugPrint('[NotificationService.permission] failed: $e\n$st');
    }
  }

  static Future<NotificationEnableResult>? _enabling;

  /// 「알림 켜기」: 권한을 다시 묻는다. 그래도 꺼져 있으면 iOS 는 이 앱의 설정 화면을
  /// 연다(한 번 거절하면 앱에서 다시 물을 수 없다). (T-261110-026)
  /// 답을 기다리는 동안 또 부르면 같은 요청의 결과를 돌려준다 — 권한 창이 떠 있을 때
  /// 다시 물으면 기기가 거절해 「손으로 켜라」는 엉뚱한 안내가 나간다.
  static Future<NotificationEnableResult> requestEnable() =>
      _enabling ??= _requestEnable().whenComplete(() => _enabling = null);

  static Future<NotificationEnableResult> _requestEnable() async {
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        await ios.requestPermissions(alert: true, badge: true, sound: true);
        await refreshPermission();
        if (enabled.value == true) return NotificationEnableResult.granted;
        final opened = await launchUrl(Uri.parse('app-settings:'));
        if (opened) return NotificationEnableResult.openedSettings;
        return NotificationEnableResult.needsManual;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        await android.requestNotificationsPermission();
        await refreshPermission();
        if (enabled.value == true) return NotificationEnableResult.granted;
      }
    } catch (e, st) {
      debugPrint('[NotificationService.requestEnable] failed: $e\n$st');
    }
    return NotificationEnableResult.needsManual;
  }

  static Future<void> _init() async {
    try {
      tz.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );

      // iOS 권한 요청
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      // Android 권한 요청
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      // Android 12+ 정확한 알람 권한 — 없으면 Doze 에서 지정시각이 지연됨
      await android?.requestExactAlarmsPermission();

      await _readPermission();
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

  /// 마지막으로 줄 선 맞추기. 아직 한 번도 안 했으면 null.
  static Future<void>? _syncTail;
  static int _syncGeneration = 0;

  /// 기기에 걸린 알림을 약 목록과 다시 맞춘다. (T-261110-023)
  /// - 전에 걸어 둔 알림(옛 판이 약마다 걸어 둔 것 포함)은 지우고 지금 계획대로만 남긴다.
  /// - 알림 준비([init])가 진행 중이면 기다린다. 준비한 적이 없거나 실패했으면 건너뛴다
  ///   (다음에 앱을 켤 때 [initAndSync] 가 다시 맞춘다).
  /// - 연달아 부르면 마지막 약 목록이 남는다. 실패해도 예외를 던지지 않는다.
  /// - 매번 전부 지우고 다시 건다. 「이미 같으면 건너뛰기」를 하지 않는 이유: 기기가
  ///   알림을 잃어도(강제 종료 등) 플러그인이 기억하는 목록은 그대로라, 건너뛰면
  ///   스스로 복구되지 않는다.
  static Future<void> syncAll(Iterable<Medicine> medicines) {
    final List<DoseSlot> plan;
    try {
      // 약 목록은 부른 순간의 것으로 굳힌다.
      plan = planSlots(medicines);
    } catch (e, st) {
      debugPrint('[NotificationService.syncAll] plan failed: $e\n$st');
      return _syncTail ?? Future<void>.value();
    }
    final generation = ++_syncGeneration;
    Future<void> apply() async {
      // 더 새 요청이 뒤에 줄 서 있으면 그쪽이 맞춘다.
      if (generation != _syncGeneration) return;
      await _applyIfReady(plan);
    }

    // 한 번에 하나씩: 앞선 맞추기가 끝난 뒤에 건다.
    final previous = _syncTail;
    return _syncTail = previous == null
        ? apply()
        : previous.then((_) => apply());
  }

  /// 예외를 던지지 않는다 — 던지면 뒤에 줄 선 맞추기가 모두 같은 예외로 끝난다.
  static Future<void> _applyIfReady(List<DoseSlot> plan) async {
    try {
      final ready = _initFuture;
      if (ready == null) return;
      await ready;
      if (!_initialized) return;
      // 걸어 둔 것만 지운다. 이미 울려서 알림창에 떠 있는 알림은 남긴다.
      await _plugin.cancelAllPendingNotifications();
    } catch (e, st) {
      // 못 지웠으면 새로 걸지 않는다 — 옛 알림과 겹쳐 두 번 울린다.
      debugPrint('[NotificationService.syncAll] failed: $e\n$st');
      return;
    }
    for (final slot in plan) {
      final daily = slot.weekday == 0;
      try {
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
      } catch (e, st) {
        // 한 시각이 실패해도 나머지 시각은 건다.
        debugPrint(
          '[NotificationService.syncAll] slot ${slot.id} failed: $e\n$st',
        );
      }
    }
  }

  /// 다음 해당 ISO 요일(1=월 … 7=일)의 지정 시:분 (현재 이후).
  static tz.TZDateTime _nextDateTimeOnWeekday(
    int isoWeekday,
    int hour,
    int minute, [
    tz.TZDateTime? at,
  ]) {
    // _nextDateTime 은 오늘/내일의 시:분만 맞춤 — 요일까지 달력 날짜로 전진.
    final first = _nextDateTime(hour, minute, at);
    final daysAhead = (isoWeekday - first.weekday) % 7;
    return tz.TZDateTime(
      tz.local,
      first.year,
      first.month,
      first.day + daysAhead,
      hour,
      minute,
    );
  }

  static tz.TZDateTime _nextDateTime(
    int hour,
    int minute, [
    tz.TZDateTime? at,
  ]) {
    final now = at ?? tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!today.isBefore(now)) return today;
    // 「24시간 뒤」가 아니라 달력으로 다음 날 — 서머타임이 바뀌는 날에도 시:분이 그대로다.
    return tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      hour,
      minute,
    );
  }

  // 테스트 전용 접근자 — 순수 계산 로직(다음 알림 시각)을 단위 테스트로 검증.
  // 동작/디자인 변경 없음(기존 private 로직을 그대로 위임).
  @visibleForTesting
  static tz.TZDateTime nextDateTimeForTest(
    int hour,
    int minute, {
    tz.TZDateTime? now,
  }) => _nextDateTime(hour, minute, now);

  @visibleForTesting
  static tz.TZDateTime nextDateTimeOnWeekdayForTest(
    int isoWeekday,
    int hour,
    int minute, {
    tz.TZDateTime? now,
  }) => _nextDateTimeOnWeekday(isoWeekday, hour, minute, now);

  /// 시험마다 처음 상태(알림 준비 전)에서 시작하게 한다.
  @visibleForTesting
  static void resetForTest() {
    _initialized = false;
    _initFuture = null;
    _syncTail = null;
    _syncGeneration = 0;
    _medicines = null;
    _enabling = null;
    enabled.value = null;
  }
}
