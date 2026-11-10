import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';

// Medicine / DoseTime 순수 로직 테스트 (Hive 박스 불필요).
// 시간대 라벨 경계, 12시간 포맷, 생성자 기본값, 오늘 복용 여부 판정.

void main() {
  group('DoseTime.periodLabel 시간대 경계', () {
    // 경계: <5 밤 / <9 아침 / <12 오전 / <14 낮 / <18 오후 / else 저녁
    final cases = <int, String>{
      0: '밤',
      4: '밤',
      5: '아침',
      8: '아침',
      9: '오전',
      11: '오전',
      12: '낮',
      13: '낮',
      14: '오후',
      17: '오후',
      18: '저녁',
      23: '저녁',
    };
    cases.forEach((hour, label) {
      test('$hour 시 → $label', () {
        expect(DoseTime(hour: hour, minute: 0).periodLabel, label);
      });
    });
  });

  group('DoseTime.format 12시간 표기', () {
    test('자정 0시 → 12시로 표기', () {
      expect(DoseTime(hour: 0, minute: 5).format(), '밤 12:05');
    });
    test('오전 한 자리 시각', () {
      expect(DoseTime(hour: 9, minute: 0).format(), '오전 9:00');
    });
    test('13시 → 1시로 표기 (13시는 낮 시간대)', () {
      expect(DoseTime(hour: 13, minute: 30).format(), '낮 1:30');
    });
    test('오후 15시 → 3시로 표기 (오후 시간대)', () {
      expect(DoseTime(hour: 15, minute: 0).format(), '오후 3:00');
    });
    test('정오 12시는 12 유지(낮)', () {
      expect(DoseTime(hour: 12, minute: 0).format(), '낮 12:00');
    });
    test('밤 23시 → 11시(저녁), 분 0패딩', () {
      expect(DoseTime(hour: 23, minute: 9).format(), '저녁 11:09');
    });
  });

  group('Medicine 생성자/필드', () {
    Medicine make({List<String>? taken}) => Medicine(
      name: '타이레놀',
      dosage: '1정',
      times: [DoseTime(hour: 8, minute: 0)],
      memo: '식후',
      createdAt: DateTime(2026, 1, 1),
      takenRecords: taken,
    );

    test('takenRecords 미지정 시 빈 리스트로 초기화', () {
      expect(make().takenRecords, isEmpty);
    });

    test('takenRecords 지정 시 보존', () {
      expect(make(taken: ['a', 'b']).takenRecords, ['a', 'b']);
    });

    test('기본 필드 보존', () {
      final m = make();
      expect(m.name, '타이레놀');
      expect(m.dosage, '1정');
      expect(m.memo, '식후');
      expect(m.times.single.hour, 8);
    });
  });

  group('Medicine.isTaken 오늘 복용 여부', () {
    // _todayKey 포맷: "yyyy-MM-dd_HH:mm" (월·일·시·분 2자리 패딩, 연도는 그대로)
    String todayKey(DoseTime t) {
      final now = DateTime.now();
      final d =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return '${d}_${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    test('오늘 키가 기록에 있으면 isTaken true', () {
      final t = DoseTime(hour: 8, minute: 0);
      final m = Medicine(
        name: 'A',
        dosage: '1',
        times: [t],
        memo: '',
        createdAt: DateTime(2026, 1, 1),
        takenRecords: [todayKey(t)],
      );
      expect(m.isTaken(t), isTrue);
    });

    test('기록 없으면 isTaken false', () {
      final t = DoseTime(hour: 8, minute: 0);
      final m = Medicine(
        name: 'A',
        dosage: '1',
        times: [t],
        memo: '',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(m.isTaken(t), isFalse);
    });

    test('다른 시각의 기록은 해당 시각 isTaken 에 영향 없음', () {
      final t8 = DoseTime(hour: 8, minute: 0);
      final t20 = DoseTime(hour: 20, minute: 0);
      final m = Medicine(
        name: 'A',
        dosage: '1',
        times: [t8, t20],
        memo: '',
        createdAt: DateTime(2026, 1, 1),
        takenRecords: [todayKey(t8)],
      );
      expect(m.isTaken(t8), isTrue);
      expect(m.isTaken(t20), isFalse);
    });
  });

  group('Medicine 복용 요일 (weekdays)', () {
    Medicine make({List<int>? weekdays}) => Medicine(
          name: 'A',
          dosage: '1',
          times: [DoseTime(hour: 8, minute: 0)],
          memo: '',
          createdAt: DateTime(2026, 1, 1),
          weekdays: weekdays,
        );

    test('weekdays 미지정 시 기본 = 매일([1..7])', () {
      final m = make();
      expect(m.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(m.activeWeekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(m.isDaily, isTrue);
    });

    test('마이그레이션: weekdays 빈값(구버전 데이터)이면 매일로 간주', () {
      final m = make(weekdays: []);
      // 저장된 raw 값은 빈 리스트지만 activeWeekdays 는 매일로 정규화.
      expect(m.weekdays, isEmpty);
      expect(m.activeWeekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(m.isDaily, isTrue);
      expect(m.isOnWeekday(3), isTrue);
    });

    test('특정 요일만 선택 시 isDaily=false, 해당 요일만 포함', () {
      final m = make(weekdays: [1, 3, 5]); // 월·수·금
      expect(m.isDaily, isFalse);
      expect(m.isOnWeekday(1), isTrue);
      expect(m.isOnWeekday(3), isTrue);
      expect(m.isOnWeekday(5), isTrue);
      expect(m.isOnWeekday(2), isFalse);
      expect(m.isOnWeekday(7), isFalse);
    });

    test('weekdayLabel: 매일이면 "매일", 아니면 월→일 정렬 라벨', () {
      expect(make().weekdayLabel, '매일');
      expect(make(weekdays: [5, 1, 3]).weekdayLabel, '월·수·금');
      expect(make(weekdays: [6, 7]).weekdayLabel, '토·일');
    });
  });
}
