import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// 기기 알림 센터 흉내. 알림 플러그인 채널 호출을 받아
/// 「지금 기기에 걸려 있는 알림」을 유지한다.
class FakeNotificationCenter {
  static const _channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  static const _timezone = MethodChannel('flutter_timezone');
  static const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

  /// 채널로 들어온 호출 이름(순서대로).
  final methods = <String>[];

  /// 알림 id → 걸린 알림.
  final pending = <int, FakeAlarm>{};

  /// 이미 울려서 알림창에 떠 있는 알림 id.
  final shown = <int>{};

  /// 이 id 의 예약은 기기가 거절한다.
  final failScheduleIds = <int>{};

  /// true 면 기기 시간대를 읽지 못한다 → 알림 준비가 실패한다.
  bool timezoneFails = false;

  /// 값이 있으면 알림 채널이 이 future 가 끝날 때까지 답하지 않는다
  /// (느리거나 멈춘 기기).
  Future<void>? hold;

  /// 걸려 있는 알림을 이른 시각부터 「요일칸 HH:mm 본문」으로.
  /// 요일칸은 매일 또는 월~일. 예: `매일 08:00 드실 약이 있어요.`
  /// 되풀이하지 않는 알림은 앞에 `한 번` 이 붙는다.
  List<String> get alarms {
    final sorted = pending.values.toList()
      ..sort((a, b) {
        final byTime = a.minuteOfDay.compareTo(b.minuteOfDay);
        return byTime != 0 ? byTime : a.weekday.compareTo(b.weekday);
      });
    return [for (final alarm in sorted) alarm.toString()];
  }

  /// 옛 판이 걸어 둔 알림처럼, 채널을 거치지 않고 미리 걸어 둔다.
  void seed(int id, {required int hour, int minute = 0, int weekday = 0}) {
    pending[id] = FakeAlarm(
      minuteOfDay: hour * 60 + minute,
      weekday: weekday,
      body: '드실 약이 있어요.',
    );
  }

  void install(TargetPlatform platform) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = platform;
    if (platform == TargetPlatform.iOS) {
      IOSFlutterLocalNotificationsPlugin.registerWith();
    } else {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    }
    messenger.setMockMethodCallHandler(_timezone, (_) async {
      if (timezoneFails) throw PlatformException(code: 'timezone_unavailable');
      return 'Asia/Seoul';
    });
    messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      final held = hold;
      if (held != null) await held;
      final args = call.arguments;
      switch (call.method) {
        case 'zonedSchedule':
          final id = args['id'] as int;
          if (failScheduleIds.contains(id)) {
            throw PlatformException(code: 'schedule_failed');
          }
          final at = DateTime.parse(args['scheduledDateTime'] as String);
          // 되풀이 방식: 매일(시각만 맞춤) / 매주(요일+시각) / 없음(한 번만).
          final match = args['matchDateTimeComponents'];
          final daily = match == DateTimeComponents.time.index;
          final weekly = match == DateTimeComponents.dayOfWeekAndTime.index;
          pending[id] = FakeAlarm(
            minuteOfDay: at.hour * 60 + at.minute,
            weekday: daily ? 0 : at.weekday,
            once: !daily && !weekly,
            body: args['body'] as String,
          );
        case 'cancelAllPendingNotifications':
          // 걸어 둔 알림만 지운다. 이미 뜬 알림은 남는다.
          pending.clear();
        case 'cancelAll':
          pending.clear();
          shown.clear();
        case 'cancel':
          final id = args is int ? args : args['id'] as int;
          pending.remove(id);
          shown.remove(id);
      }
      return true;
    });
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_timezone, null);
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  }
}

class FakeAlarm {
  FakeAlarm({
    required this.minuteOfDay,
    required this.weekday,
    required this.body,
    this.once = false,
  });

  final int minuteOfDay;

  /// 0 = 매일, 1..7 = 월~일.
  final int weekday;
  final String body;

  /// 되풀이 없이 한 번만 울리는 알림.
  final bool once;

  @override
  String toString() {
    final day = weekday == 0
        ? '매일'
        : FakeNotificationCenter._weekdayNames[weekday - 1];
    final hh = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final mm = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '${once ? '한 번 ' : ''}$day $hh:$mm $body';
  }
}
