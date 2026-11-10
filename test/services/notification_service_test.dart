import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:yakmukja/services/notification_service.dart';

// 복약 알림 순수 계산 로직: 다음 알림 시각(_nextDateTime). 알림 계획은 notification_plan_test.dart.
// @visibleForTesting 접근자로 검증(플러그인 미가용 환경에서도 동작 — tz 만 필요).

void main() {
  setUp(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
  });

  group('nextDateTime — 다음 알림 시각', () {
    test('항상 현재 이후이며, 지정한 시:분과 24시간 이내', () {
      final now = tz.TZDateTime.now(tz.local);
      for (final hm in [
        [now.hour, now.minute], // 동일 시각
        [(now.hour + 2) % 24, 0], // 미래 가능성
        [(now.hour + 23) % 24, 30], // 과거 가능성 → +1일 롤오버 경로
      ]) {
        final r = NotificationService.nextDateTimeForTest(hm[0], hm[1]);
        expect(r.hour, hm[0]);
        expect(r.minute, hm[1]);
        expect(r.isBefore(now), isFalse, reason: '결과는 항상 현재 이후여야 함');
        expect(r.difference(now).inHours < 24, isTrue);
      }
    });

    test('과거 시각은 다음날로 롤오버되어 현재 이후가 된다', () {
      final now = tz.TZDateTime.now(tz.local);
      final past = now.subtract(const Duration(minutes: 30));
      final r = NotificationService.nextDateTimeForTest(past.hour, past.minute);
      // today at past-time 이 현재보다 이르면 +1일; 결과는 항상 현재 이후.
      expect(r.isBefore(now), isFalse);
      expect(r.hour, past.hour);
      expect(r.minute, past.minute);
    });
  });

  group('nextDateTimeOnWeekday — 특정 요일 다음 발생', () {
    test('결과 요일이 지정 ISO 요일과 일치하고 시:분 유지, 현재 이후', () {
      final now = tz.TZDateTime.now(tz.local);
      for (int wd = 1; wd <= 7; wd++) {
        final r = NotificationService.nextDateTimeOnWeekdayForTest(wd, 9, 30);
        expect(r.weekday, wd, reason: '결과 요일이 지정 요일이어야 함');
        expect(r.hour, 9);
        expect(r.minute, 30);
        expect(r.isBefore(now), isFalse);
        // 같은 요일/시각은 최대 7일 안에 다시 온다.
        expect(r.difference(now).inDays < 7, isTrue);
      }
    });
  });

  // 하루를 「24시간 뒤」로 세면 서머타임이 바뀌는 날 시:분이 1시간 밀린다.
  // 그 밀린 시각이 되풀이 알림의 기준이 되므로, 다음에 다시 맞출 때까지 계속 틀린다.
  group('서머타임이 바뀌는 날에도 시:분이 그대로다', () {
    setUp(() {
      // 뉴욕은 2026-11-01 02:00 에 서머타임이 끝난다.
      tz.setLocalLocation(tz.getLocation('America/New_York'));
    });

    test('서머타임이 끝나기 전날, 이미 지난 시각은 다음 날 같은 시:분으로 걸린다', () {
      final now = tz.TZDateTime(tz.local, 2026, 10, 31, 9);

      final r = NotificationService.nextDateTimeForTest(8, 0, now: now);

      expect([r.year, r.month, r.day, r.hour, r.minute], [2026, 11, 1, 8, 0]);
    });

    test('요일 알림은 서머타임이 끝나는 주를 넘어가도 같은 시:분으로 걸린다', () {
      final now = tz.TZDateTime(tz.local, 2026, 10, 28, 9); // 수요일

      final r = NotificationService.nextDateTimeOnWeekdayForTest(
        DateTime.monday,
        8,
        0,
        now: now,
      );

      expect(
        [r.year, r.month, r.day, r.hour, r.minute, r.weekday],
        [2026, 11, 2, 8, 0, DateTime.monday],
      );
    });
  });
}
