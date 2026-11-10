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

  /// 걸려 있는 알림을 이른 시각부터 「요일칸 HH:mm 본문」으로.
  /// 요일칸은 매일 또는 월~일. 예: `매일 08:00 드실 약이 있어요.`
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
    messenger.setMockMethodCallHandler(_timezone, (_) async => 'Asia/Seoul');
    messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      final args = call.arguments;
      switch (call.method) {
        case 'zonedSchedule':
          final at = DateTime.parse(args['scheduledDateTime'] as String);
          final daily =
              args['matchDateTimeComponents'] == DateTimeComponents.time.index;
          pending[args['id'] as int] = FakeAlarm(
            minuteOfDay: at.hour * 60 + at.minute,
            weekday: daily ? 0 : at.weekday,
            body: args['body'] as String,
          );
        case 'cancelAllPendingNotifications':
        case 'cancelAll':
          pending.clear();
        case 'cancel':
          pending.remove(args is int ? args : args['id'] as int);
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
  });

  final int minuteOfDay;

  /// 0 = 매일, 1..7 = 월~일.
  final int weekday;
  final String body;

  @override
  String toString() {
    final day = weekday == 0
        ? '매일'
        : FakeNotificationCenter._weekdayNames[weekday - 1];
    final hh = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final mm = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$day $hh:$mm $body';
  }
}
