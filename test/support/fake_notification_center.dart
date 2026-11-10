import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기기 알림 센터 흉내. 알림 플러그인 채널 호출을 받아
/// 「지금 기기에 걸려 있는 알림」을 유지한다.
class FakeNotificationCenter {
  static const _channel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  static const _timezone = MethodChannel('flutter_timezone');
  static const _urlLauncher = MethodChannel('plugins.flutter.io/url_launcher');
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

  /// 기기 설정에서 이 앱의 알림이 켜져 있는지.
  bool enabled = true;

  /// 앱이 권한을 다시 물었을 때 사용자가 허용하는지.
  bool grantOnRequest = true;

  /// 앱이 연 주소(설정 화면 등).
  final launchedUrls = <String>[];

  /// true 면 기기가 주소를 열지 못한다.
  bool launchFails = false;

  /// true 면 알림 권한 상태를 읽지 못한다.
  bool permissionReadFails = false;

  /// initialize 에 넘긴 인자. iOS 카테고리 단추를 여기서 본다.
  Map<String, Object?>? initializeArgs;

  /// 단추로 앱이 켜진 척할 때 넣는다. null 이면 단추로 켜지지 않았다.
  /// 키는 플러그인의 getNotificationAppLaunchDetails 응답과 같다.
  Map<String, Object?>? launchResponse;

  late TargetPlatform _platform;

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

  /// 한 번만 울리는 알림을 이른 날짜부터 「yyyy-MM-dd HH:mm 본문」으로.
  List<String> get onceAlarms {
    final once = [
      for (final alarm in pending.values)
        if (alarm.once && alarm.at != null) alarm,
    ]..sort((a, b) => a.at!.compareTo(b.at!));
    String two(int n) => n.toString().padLeft(2, '0');
    return [
      for (final alarm in once)
        '${alarm.at!.year}-${two(alarm.at!.month)}-${two(alarm.at!.day)} '
            '${two(alarm.at!.hour)}:${two(alarm.at!.minute)} ${alarm.body}',
    ];
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
    _platform = platform;
    debugDefaultTargetPlatformOverride = platform;
    // 다시 알림 목록은 SharedPreferences 에 있다. 시험마다 빈 목록에서 시작한다.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (platform == TargetPlatform.iOS) {
      IOSFlutterLocalNotificationsPlugin.registerWith();
    } else {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    }
    messenger.setMockMethodCallHandler(_timezone, (_) async {
      if (timezoneFails) throw PlatformException(code: 'timezone_unavailable');
      return 'Asia/Seoul';
    });
    messenger.setMockMethodCallHandler(_urlLauncher, (call) async {
      if (call.method == 'launch') {
        launchedUrls.add((call.arguments as Map)['url'] as String);
        return !launchFails;
      }
      return true;
    });
    messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      final held = hold;
      if (held != null) await held;
      final args = call.arguments;
      switch (call.method) {
        case 'initialize':
          if (args is Map) {
            initializeArgs = Map<String, Object?>.from(args);
          }
          break;
        case 'getNotificationAppLaunchDetails':
          final response = launchResponse;
          if (response == null) {
            return <String, Object?>{'notificationLaunchedApp': false};
          }
          return <String, Object?>{
            'notificationLaunchedApp': true,
            'notificationResponse': response,
          };
        case 'checkPermissions':
          if (permissionReadFails) {
            throw PlatformException(code: 'permission_read_failed');
          }
          return <String, Object?>{
            'isEnabled': enabled,
            'isAlertEnabled': enabled,
            'isBadgeEnabled': enabled,
            'isSoundEnabled': enabled,
          };
        case 'areNotificationsEnabled':
          if (permissionReadFails) {
            throw PlatformException(code: 'permission_read_failed');
          }
          return enabled;
        case 'requestPermissions':
        case 'requestNotificationsPermission':
          if (grantOnRequest) enabled = true;
          return enabled;
        case 'zonedSchedule':
          final id = args['id'] as int;
          // iOS 는 알림 권한이 없으면 예약 자체가 실패한다
          // (UNErrorCodeNotificationsNotAllowed). 안드로이드는 예약은 되고 표시만 안 된다.
          if (!enabled && _platform == TargetPlatform.iOS) {
            throw PlatformException(code: 'notifications_not_allowed');
          }
          if (failScheduleIds.contains(id)) {
            throw PlatformException(code: 'schedule_failed');
          }
          final at = DateTime.parse(args['scheduledDateTime'] as String);
          // 되풀이 방식: 매일(시각만 맞춤) / 매주(요일+시각) / 없음(한 번만).
          final match = args['matchDateTimeComponents'];
          final daily = match == DateTimeComponents.time.index;
          final weekly = match == DateTimeComponents.dayOfWeekAndTime.index;
          final specifics = args['platformSpecifics'];
          pending[id] = FakeAlarm(
            minuteOfDay: at.hour * 60 + at.minute,
            weekday: daily ? 0 : at.weekday,
            once: !daily && !weekly,
            at: !daily && !weekly ? at : null,
            body: args['body'] as String,
            payload: args['payload'] as String? ?? '',
            platformSpecifics: specifics is Map
                ? Map<String, Object?>.from(specifics)
                : null,
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

  /// 떠 있는 앱에 알림 응답을 넣는다. 형식은 didReceiveNotificationResponse.
  /// [notificationResponseType] 0 = 알림 본문, 1 = 단추.
  Future<void> deliverResponse({
    required int notificationResponseType,
    String? actionId,
    String? payload,
    int id = 1,
  }) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall('didReceiveNotificationResponse', <String, Object?>{
        'notificationId': id,
        'actionId': actionId,
        'input': '',
        'payload': payload ?? '',
        'notificationResponseType': notificationResponseType,
      }),
    );
    await messenger.handlePlatformMessage(_channel.name, data, (_) {});
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_timezone, null);
    messenger.setMockMethodCallHandler(_urlLauncher, null);
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
    this.at,
    this.payload = '',
    this.platformSpecifics,
  });

  final int minuteOfDay;

  /// 0 = 매일, 1..7 = 월~일.
  final int weekday;
  final String body;

  /// 되풀이 없이 한 번만 울리는 알림.
  final bool once;

  /// 한 번만 울리는 알림이 울릴 날짜·시각.
  final DateTime? at;

  /// 알림에 실어 보낸 payload. 약 시각은 `dose:HH:mm`.
  final String payload;

  /// 플랫폼별 알림 설정(단추·카테고리).
  final Map<String, Object?>? platformSpecifics;

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
