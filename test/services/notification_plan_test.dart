import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

/// 약 목록 → 울려야 할 알림 계획. 같은 시각 약은 알림 1건으로 묶는다.
/// (T-261110-023 — 아침 8시 약이 3개면 똑같은 알림이 3번 오던 문제)
Medicine med(
  String name,
  List<List<int>> times, {
  List<int>? weekdays,
  DateTime? deletedAt,
}) => Medicine(
  name: name,
  dosage: '1알',
  times: [for (final t in times) DoseTime(hour: t[0], minute: t[1])],
  memo: '',
  createdAt: DateTime(2026, 11, 1),
  weekdays: weekdays,
  deletedAt: deletedAt,
);

/// (시, 분, 요일칸, 약 개수) — 요일칸 0 = 매일, 1..7 = 월~일.
List<(int, int, int, int)> shape(List<DoseSlot> slots) => [
  for (final s in slots) (s.hour, s.minute, s.weekday, s.count),
];

void main() {
  test('매일 08:00 약 3개는 매일 08:00 알림 1건(약 3개)이 된다', () {
    final slots = NotificationService.planSlots([
      med('혈압약', [
        [8, 0],
      ]),
      med('오메가3', [
        [8, 0],
      ]),
      med('비타민D', [
        [8, 0],
      ]),
    ]);

    expect(shape(slots), [(8, 0, 0, 3)]);
  });

  test('시각이 다르면 시각마다 1건이고 이른 시각부터 나온다', () {
    final slots = NotificationService.planSlots([
      med('A', [
        [20, 0],
        [8, 0],
      ]),
      med('B', [
        [8, 0],
      ]),
    ]);

    expect(shape(slots), [(8, 0, 0, 2), (20, 0, 0, 1)]);
  });

  test('매일 약과 월·수·금 약이 같은 시각이면 요일마다 개수가 다른 알림이 된다', () {
    final slots = NotificationService.planSlots([
      med('매일약', [
        [8, 0],
      ]),
      med(
        '월수금약',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
      ),
    ]);

    expect(shape(slots), [
      (8, 0, 1, 2),
      (8, 0, 2, 1),
      (8, 0, 3, 2),
      (8, 0, 4, 1),
      (8, 0, 5, 2),
      (8, 0, 6, 1),
      (8, 0, 7, 1),
    ]);
  });

  test('평일만 먹는 약은 평일 5건만 예약하고 주말은 없다', () {
    final slots = NotificationService.planSlots([
      med(
        '평일약',
        [
          [8, 0],
        ],
        weekdays: [1, 2, 3, 4, 5],
      ),
    ]);

    expect(shape(slots), [
      (8, 0, 1, 1),
      (8, 0, 2, 1),
      (8, 0, 3, 1),
      (8, 0, 4, 1),
      (8, 0, 5, 1),
    ]);
  });

  test('휴지통 약은 알림에서 빠진다', () {
    final slots = NotificationService.planSlots([
      med('혈압약', [
        [8, 0],
      ]),
      med('버린약', [
        [8, 0],
        [21, 0],
      ], deletedAt: DateTime(2026, 11, 9)),
    ]);

    expect(shape(slots), [(8, 0, 0, 1)]);
  });

  test('평일만 먹는 약 5개 × 하루 3번도 15건이다 (iOS 대기 알림 상한 64 안쪽)', () {
    final slots = NotificationService.planSlots([
      for (var i = 0; i < 5; i++)
        med(
          '평일약$i',
          [
            [8, 0],
            [13, 0],
            [19, 0],
          ],
          weekdays: [1, 2, 3, 4, 5],
        ),
    ]);

    expect(slots.length, 15);
    expect(slots.map((s) => s.count).toSet(), {5});
  });

  test('알림 id 는 (시각 × 요일칸)마다 다르다', () {
    final slots = NotificationService.planSlots([
      med('매일약', [
        [8, 0],
        [20, 0],
      ]),
      med(
        '월수금약',
        [
          [8, 0],
        ],
        weekdays: [1, 3, 5],
      ),
    ]);

    expect(slots.length, 8);
    expect(slots.map((s) => s.id).toSet().length, 8);
  });
}
