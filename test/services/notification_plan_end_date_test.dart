import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

/// 끝나는 날이 있는 약의 알림 계획. 반복 알림은 스스로 멈추지 못하므로, 끝나는 약은
/// 남은 날짜마다 한 번씩 울리는 알림으로 건다. (T-261110-042)
Medicine med(
  String name,
  List<List<int>> times, {
  List<int>? weekdays,
  DateTime? endDate,
  DateTime? deletedAt,
}) => Medicine(
  name: name,
  dosage: '1알',
  times: [for (final t in times) DoseTime(hour: t[0], minute: t[1])],
  memo: '',
  createdAt: DateTime(2026, 11, 1),
  weekdays: weekdays,
  endDate: endDate,
  deletedAt: deletedAt,
);

/// 반복 알림: (시, 분, 요일칸, 본문).
List<(int, int, int, String)> repeating(List<DoseSlot> slots) => [
  for (final s in slots)
    if (s.date == null) (s.hour, s.minute, s.weekday, s.body),
];

/// 한 번 울리는 알림: 「11/10 08:00 ×1」.
List<String> oneOffs(List<DoseSlot> slots) => [
  for (final s in slots)
    if (s.date != null)
      '${s.date!.month}/${s.date!.day} '
          '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')} '
          '×${s.count}',
];

void main() {
  // 2026-11-10 은 화요일이다.
  final morning = DateTime(2026, 11, 10, 7, 0);

  List<DoseSlot> plan(
    List<Medicine> medicines, {
    DateTime? now,
    int maxPending = 60,
  }) => NotificationService.planSlots(
    medicines,
    now: now ?? morning,
    maxPending: maxPending,
  );

  test('끝나는 날이 있는 약은 오늘부터 그날까지 날짜마다 한 번씩 울린다', () {
    final slots = plan([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 12)),
    ]);

    expect(repeating(slots), isEmpty);
    expect(oneOffs(slots), [
      '11/10 08:00 ×1',
      '11/11 08:00 ×1',
      '11/12 08:00 ×1',
    ]);
  });

  test('끝난 약(끝나는 날이 어제)은 알림이 없다', () {
    final slots = plan([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 9)),
    ]);

    expect(slots, isEmpty);
  });

  test('오늘 이미 지난 시각은 걸지 않는다', () {
    final slots = plan([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 12)),
    ], now: DateTime(2026, 11, 10, 9, 0));

    expect(oneOffs(slots), ['11/11 08:00 ×1', '11/12 08:00 ×1']);
  });

  test('끝나는 날이 오늘이면 오늘 남은 시각만 건다', () {
    final slots = plan([
      med('항생제', [
        [8, 0],
        [21, 0],
      ], endDate: DateTime(2026, 11, 10)),
    ], now: DateTime(2026, 11, 10, 9, 0));

    expect(oneOffs(slots), ['11/10 21:00 ×1']);
  });

  test('요일을 정한 약은 기간 안의 그 요일 날짜만 건다', () {
    final slots = plan([
      // 월·수·금, 11/16(월)까지.
      med(
        '주사',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
        endDate: DateTime(2026, 11, 16),
      ),
    ]);

    expect(oneOffs(slots), [
      '11/11 08:00 ×1',
      '11/13 08:00 ×1',
      '11/16 08:00 ×1',
    ]);
  });

  test('끝나는 약 둘이 같은 날 같은 시각이면 1건으로 묶고 개수를 말한다', () {
    final slots = plan([
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 11)),
      med('소화제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 12)),
    ]);

    expect(oneOffs(slots), [
      '11/10 08:00 ×2',
      '11/11 08:00 ×2',
      '11/12 08:00 ×1',
    ]);
    final first = slots.firstWhere((s) => s.date != null);
    expect(first.body, '드실 약이 2개 있어요.');
  });

  test('계속 먹는 약과 같은 시각이면 따로 걸지 않고, 그 반복 알림은 개수를 말하지 않는다', () {
    final slots = plan([
      med('혈압약', [
        [8, 0],
      ]),
      med('비타민', [
        [8, 0],
      ]),
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 12)),
    ]);

    // 개수가 날마다 달라진다(지금 3개, 끝난 뒤 2개) — 틀린 개수를 말하지 않는다.
    expect(repeating(slots), [(8, 0, 0, '드실 약이 있어요.')]);
    expect(oneOffs(slots), isEmpty);
  });

  test('계속 먹는 약이 없는 시각은 한 번씩 울리는 알림으로 따로 건다', () {
    final slots = plan([
      med('혈압약', [
        [8, 0],
      ]),
      med('항생제', [
        [8, 0],
        [21, 0],
      ], endDate: DateTime(2026, 11, 11)),
    ]);

    expect(repeating(slots), [(8, 0, 0, '드실 약이 있어요.')]);
    expect(oneOffs(slots), ['11/10 21:00 ×1', '11/11 21:00 ×1']);
  });

  test('계속 먹는 약이 그 요일에 없으면 그날은 한 번 울리는 알림을 건다', () {
    final slots = plan([
      // 월·수·금만.
      med(
        '주사',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
      ),
      // 매일, 11/12(목)까지.
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 12)),
    ]);

    // 수요일(11/11)만 겹친다 — 그 요일 반복 알림만 개수를 빼고, 월·금은 그대로다.
    expect(repeating(slots), [
      (8, 0, 1, '드실 약이 있어요.'),
      (8, 0, 3, '드실 약이 있어요.'),
      (8, 0, 5, '드실 약이 있어요.'),
    ]);
    expect(oneOffs(slots), ['11/10 08:00 ×1', '11/12 08:00 ×1']);
  });

  test('겹치지 않는 요일의 반복 알림은 개수를 그대로 말한다', () {
    final slots = plan([
      med(
        '주사',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
      ),
      med(
        '영양제',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
      ),
      // 수요일(11/11) 하루만 겹친다.
      med('항생제', [
        [8, 0],
      ], endDate: DateTime(2026, 11, 11)),
    ]);

    expect(repeating(slots), [
      (8, 0, 1, '드실 약이 2개 있어요.'),
      (8, 0, 3, '드실 약이 있어요.'),
      (8, 0, 5, '드실 약이 2개 있어요.'),
    ]);
  });

  test('휴지통에 있는 끝나는 약은 뺀다', () {
    final slots = plan([
      med(
        '항생제',
        [
          [8, 0],
        ],
        endDate: DateTime(2026, 11, 12),
        deletedAt: DateTime(2026, 11, 10),
      ),
    ]);

    expect(slots, isEmpty);
  });

  test('한 번 울리는 알림은 가까운 날짜부터 상한까지만 건다', () {
    final slots = plan([
      med('혈압약', [
        [7, 30],
      ]),
      // 하루 3번, 60일 동안 = 180건.
      med('한약', [
        [8, 0],
        [13, 0],
        [19, 0],
      ], endDate: DateTime(2027, 1, 8)),
    ], maxPending: 10);

    // 반복 1건 + 한 번 울리는 알림 9건 = 10건.
    expect(slots, hasLength(10));
    expect(oneOffs(slots), [
      '11/10 08:00 ×1',
      '11/10 13:00 ×1',
      '11/10 19:00 ×1',
      '11/11 08:00 ×1',
      '11/11 13:00 ×1',
      '11/11 19:00 ×1',
      '11/12 08:00 ×1',
      '11/12 13:00 ×1',
      '11/12 19:00 ×1',
    ]);
  });

  test('알림 id 는 모두 다르고, 한 번 울리는 알림은 반복 알림과 겹치지 않는다', () {
    final slots = plan([
      med(
        '주사',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
      ),
      med('한약', [
        [8, 0],
        [13, 0],
        [19, 0],
      ], endDate: DateTime(2026, 12, 10)),
    ]);

    final ids = [for (final s in slots) s.id];
    expect(ids.toSet(), hasLength(ids.length));
    final repeatingIds = {
      for (final s in slots)
        if (s.date == null) s.id,
    };
    for (final s in slots.where((s) => s.date != null)) {
      expect(repeatingIds.contains(s.id), isFalse);
      expect(s.id, greaterThan(914397)); // 반복 알림 id 의 최댓값보다 크다.
    }
  });

  test('끝나는 날이 없는 약만 있으면 종전과 같다', () {
    final slots = plan([
      med('혈압약', [
        [8, 0],
      ]),
      med('오메가3', [
        [8, 0],
      ]),
    ]);

    expect(repeating(slots), [(8, 0, 0, '드실 약이 2개 있어요.')]);
    expect(oneOffs(slots), isEmpty);
  });
}
