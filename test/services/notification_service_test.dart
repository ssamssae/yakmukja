import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

// 복약 알림 순수 계산 로직: 다음 알림 시각(_nextDateTime), 알림 id(_notificationId).
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

  group('notificationId — 다중 복용시간 id 산출', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('yakmukja_notif_test');
      Hive.init(tmp.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    });

    tearDown(() async {
      await Hive.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('박스 저장(key=int) 시 key*100+timeIndex, 복용시간마다 고유', () async {
      final box = await Hive.openBox<Medicine>('meds');
      final m = Medicine(
        name: 'A',
        dosage: '1',
        times: [
          DoseTime(hour: 8, minute: 0),
          DoseTime(hour: 13, minute: 0),
          DoseTime(hour: 20, minute: 0),
        ],
        memo: '',
        createdAt: DateTime(2026, 1, 1),
      );
      await box.add(m);
      final key = m.key as int;

      final ids = [
        NotificationService.notificationIdForTest(m, 0),
        NotificationService.notificationIdForTest(m, 1),
        NotificationService.notificationIdForTest(m, 2),
      ];
      expect(ids, [key * 100 + 0, key * 100 + 1, key * 100 + 2]);
      expect(ids.toSet().length, 3, reason: '복용시간마다 id 가 고유해야 함');
    });

    test('박스 저장 전(key=null)이면 null 반환해 스케줄 생략', () {
      final m = Medicine(
        name: 'A',
        dosage: '1',
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(NotificationService.notificationIdForTest(m, 0), isNull);
    });
  });
}
