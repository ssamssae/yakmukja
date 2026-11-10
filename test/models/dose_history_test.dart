import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/dose_history.dart';
import 'package:yakmukja/models/medicine.dart';

/// 지난 날의 복용 기록을 날짜별로 묶는다. (T-261110-039)
void main() {
  // 2026-11-10 은 화요일이다.
  final today = DateTime(2026, 11, 10, 9, 30);

  Medicine medicine(
    String name, {
    List<(int, int)> times = const [(8, 0)],
    String dosage = '1알',
    DateTime? createdAt,
    List<String> taken = const [],
    List<int>? weekdays,
    DateTime? deletedAt,
  }) => Medicine(
    name: name,
    dosage: dosage,
    times: [for (final (h, m) in times) DoseTime(hour: h, minute: m)],
    memo: '',
    createdAt: createdAt ?? DateTime(2026, 10, 1),
    takenRecords: [...taken],
    weekdays: weekdays,
    deletedAt: deletedAt,
  );

  String line(HistoryDose dose) =>
      '${dose.hour}:${dose.minute.toString().padLeft(2, '0')} ${dose.name} ${dose.taken ? 'O' : 'X'}';

  test('기록 키는 「yyyy-MM-dd_HH:mm」이다', () {
    expect(
      Medicine.recordKey(DateTime(2026, 1, 5, 23, 59), 8, 5),
      '2026-01-05_08:05',
    );
  });

  test('어제 먹은 약과 안 먹은 약이 그날 묶음에 시간순으로 나온다', () {
    final history = buildDoseHistory([
      medicine('수면 보조제', times: [(21, 30)]),
      medicine('혈압약', taken: ['2026-11-09_08:00']),
    ], today);

    final yesterday = history.first;
    expect(yesterday.date, DateTime(2026, 11, 9));
    expect(yesterday.doses.map(line), ['8:00 혈압약 O', '21:30 수면 보조제 X']);
    expect(yesterday.takenCount, 1);
    expect(yesterday.total, 2);
  });

  test('오늘은 지난 기록에 넣지 않는다', () {
    final history = buildDoseHistory([
      medicine('혈압약', taken: ['2026-11-10_08:00']),
    ], today);

    expect(history.first.date, DateTime(2026, 11, 9));
    expect(history.any((day) => day.date == DateTime(2026, 11, 10)), isFalse);
  });

  test('최근 30일까지만 거슬러 간다', () {
    final history = buildDoseHistory([
      medicine('혈압약', createdAt: DateTime(2026, 1, 1)),
    ], today);

    expect(history, hasLength(30));
    expect(history.last.date, DateTime(2026, 10, 11));
  });

  test('등록하기 전 날짜에는 그 약이 나오지 않는다', () {
    final history = buildDoseHistory([
      medicine('혈압약', createdAt: DateTime(2026, 11, 8, 7, 0)),
    ], today);

    expect(history.map((day) => day.date), [
      DateTime(2026, 11, 9),
      DateTime(2026, 11, 8),
    ]);
  });

  test('등록한 날에는 등록한 시각 뒤의 약만 나온다', () {
    final history = buildDoseHistory([
      medicine(
        '혈압약',
        times: [(8, 0), (21, 0)],
        createdAt: DateTime(2026, 11, 9, 15, 0),
      ),
    ], today);

    expect(history.single.date, DateTime(2026, 11, 9));
    expect(history.single.doses.map(line), ['21:00 혈압약 X']);
  });

  test('등록한 날의 이른 시각 체크가 저녁 놓침을 숨기지 않는다', () {
    // 15:00 에 등록, 시각은 8:00·21:00. 홈은 8:00 도 체크할 수 있다.
    final history = buildDoseHistory([
      medicine(
        '혈압약',
        times: [(8, 0), (21, 0)],
        createdAt: DateTime(2026, 11, 9, 15, 0),
        taken: ['2026-11-09_08:00'],
      ),
    ], today);

    expect(history.single.doses.map(line), ['8:00 혈압약 O', '21:00 혈압약 X']);
  });

  test('저녁 시각을 바꾼 뒤에도 아침 놓침이 보인다', () {
    // 지금은 9:00·22:00. 어제는 21:00 만 체크했다.
    final history = buildDoseHistory([
      medicine('혈압약', times: [(9, 0), (22, 0)], taken: ['2026-11-09_21:00']),
    ], today);

    expect(history.first.doses.map(line), ['9:00 혈압약 X', '21:00 혈압약 O']);
  });

  test('등록한 날의 이른 옛 시각 체크는 등록 뒤 놓침을 지우지 않는다', () {
    // 15:00 등록, 지금은 9:00·22:00. 8:00 체크는 등록 전 9:00 과 가깝다.
    final history = buildDoseHistory([
      medicine(
        '혈압약',
        times: [(9, 0), (22, 0)],
        createdAt: DateTime(2026, 11, 9, 15, 0),
        taken: ['2026-11-09_08:00'],
      ),
    ], today);

    expect(history.single.doses.map(line), ['8:00 혈압약 O', '22:00 혈압약 X']);
  });

  test('달이 바뀌어도 어제는 전달 마지막 날이다', () {
    final nov1 = DateTime(2026, 11, 1, 8, 0);
    final history = buildDoseHistory([
      medicine(
        '혈압약',
        createdAt: DateTime(2026, 10, 1),
        taken: ['2026-10-31_08:00'],
      ),
    ], nov1);

    expect(history, hasLength(30));
    expect(history.first.date, DateTime(2026, 10, 31));
    expect(history.first.doses.map(line), ['8:00 혈압약 O']);
    expect(history.last.date, DateTime(2026, 10, 2));
  });

  test('요일을 정한 약은 그 요일에만 나오고, 약이 없던 날은 건너뛴다', () {
    final history = buildDoseHistory([
      // 월·수·금.
      medicine('비타민', weekdays: [1, 3, 5], createdAt: DateTime(2026, 11, 1)),
    ], today);

    expect(history.map((day) => day.date), [
      DateTime(2026, 11, 9), // 월
      DateTime(2026, 11, 6), // 금
      DateTime(2026, 11, 4), // 수
      DateTime(2026, 11, 2), // 월
    ]);
  });

  test('휴지통 약은 나오지 않는다', () {
    final history = buildDoseHistory([
      medicine(
        '혈압약',
        taken: ['2026-11-09_08:00'],
        deletedAt: DateTime(2026, 11, 10),
      ),
    ], today);

    expect(history, isEmpty);
  });

  test('시간을 바꾼 약의 옛 체크는 기록된 시각 그대로 먹은 것으로 나온다', () {
    final history = buildDoseHistory([
      // 지금은 9:00 이지만 어제는 8:00 에 체크했다.
      medicine('혈압약', times: [(9, 0)], taken: ['2026-11-09_08:00']),
    ], today);

    // 바뀐 시각(9:00)을 「기록 없음」으로 또 세지 않는다.
    expect(history.first.doses.map(line), ['8:00 혈압약 O']);
  });

  test('하루 두 번 약에서 한 번만 옛 시각으로 체크했으면 한 번은 기록 없음이다', () {
    final history = buildDoseHistory([
      medicine('혈압약', times: [(9, 0), (21, 0)], taken: ['2026-11-09_08:00']),
    ], today);

    expect(history.first.doses.map(line), ['8:00 혈압약 O', '21:00 혈압약 X']);
  });

  test('먹는 요일이 아니던 날의 체크도 먹은 것으로 나온다', () {
    final history = buildDoseHistory([
      // 지금은 월·수·금이지만 일요일(11/8)에 체크한 기록이 있다.
      medicine(
        '비타민',
        weekdays: [1, 3, 5],
        taken: ['2026-11-08_08:00'],
        createdAt: DateTime(2026, 11, 7),
      ),
    ], today);

    final sunday = history.firstWhere(
      (day) => day.date == DateTime(2026, 11, 8),
    );
    expect(sunday.doses.map(line), ['8:00 비타민 O']);
  });

  test('같은 시각이면 이름순이고 복용량은 그대로 전한다', () {
    final history = buildDoseHistory([
      medicine('혈압약', dosage: ''),
      medicine('비타민', dosage: '2캡슐'),
    ], today);

    expect(history.first.doses.map((dose) => '${dose.name}/${dose.dosage}'), [
      '비타민/2캡슐',
      '혈압약/',
    ]);
  });

  test('30일보다 오래된 기록은 쓰지 않는다', () {
    final history = buildDoseHistory([
      medicine(
        '비타민',
        weekdays: [1],
        createdAt: DateTime(2026, 1, 1),
        taken: ['2026-10-05_08:00'],
      ),
    ], today);

    expect(
      history.every((day) => !day.date.isBefore(DateTime(2026, 10, 11))),
      isTrue,
    );
  });
}
