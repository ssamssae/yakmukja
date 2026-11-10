import 'medicine.dart';

/// 지난 기록으로 보여 주는 날 수(어제부터 거꾸로). 복용 기록은 앱을 켤 때
/// 30일 넘은 것을 정리한다([Medicine.pruneOldRecords]). (T-261110-039)
const int doseHistoryDays = 30;

/// 지난 하루의 약 한 줄.
class HistoryDose {
  const HistoryDose({
    required this.name,
    required this.dosage,
    required this.hour,
    required this.minute,
    required this.taken,
  });

  final String name;
  final String dosage;
  final int hour;
  final int minute;

  /// 그날 그 시각에 「먹었어요」를 표시했는가. false 는 「기록 없음」이다 —
  /// 안 먹었다고 단정하지 않는다.
  final bool taken;

  int get minuteOfDay => hour * 60 + minute;
}

/// 지난 하루의 기록.
class HistoryDay {
  const HistoryDay({required this.date, required this.doses});

  /// 그날 0시.
  final DateTime date;

  /// 시간순, 같은 시각이면 이름순.
  final List<HistoryDose> doses;

  int get total => doses.length;
  int get takenCount => doses.where((dose) => dose.taken).length;
}

/// 어제부터 거꾸로 [days]일의 기록. 약이 없던 날은 건너뛴다. 오늘은 넣지 않는다.
///
/// 그날의 예정은 지금 약 설정(요일·시간·등록일)으로 계산한다. 설정을 바꾸기 전의
/// 예정은 남아 있지 않기 때문이다. 그래서:
/// - 그날 표시한 기록이 있으면 지금 설정과 달라도(시간·요일을 바꿨어도) 먹은 것으로 넣는다.
/// - 그런 기록 한 건마다 그 약의 「기록 없음」 한 건을 뺀다 — 시간을 옮긴 약을
///   「먹음 + 기록 없음」 두 줄로 세지 않는다.
/// - 등록한 날에는 등록한 시각 뒤의 약만 예정으로 본다.
/// 휴지통 약은 뺀다.
List<HistoryDay> buildDoseHistory(
  Iterable<Medicine> medicines,
  DateTime today, {
  int days = doseHistoryDays,
}) {
  final active = [
    for (final medicine in medicines)
      if (medicine.deletedAt == null) medicine,
  ];
  final history = <HistoryDay>[];
  for (var back = 1; back <= days; back++) {
    // 달력 날짜로 거슬러 간다(서머타임이 바뀌는 날에도 하루씩).
    final date = DateTime(today.year, today.month, today.day - back);
    final doses = <HistoryDose>[];
    for (final medicine in active) {
      doses.addAll(_dosesOn(medicine, date));
    }
    if (doses.isEmpty) continue;
    doses.sort((a, b) {
      final byTime = a.minuteOfDay.compareTo(b.minuteOfDay);
      return byTime != 0 ? byTime : a.name.compareTo(b.name);
    });
    history.add(HistoryDay(date: date, doses: doses));
  }
  return history;
}

List<HistoryDose> _dosesOn(Medicine medicine, DateTime date) {
  HistoryDose dose(int minuteOfDay, {required bool taken}) => HistoryDose(
    name: medicine.name,
    dosage: medicine.dosage,
    hour: minuteOfDay ~/ 60,
    minute: minuteOfDay % 60,
    taken: taken,
  );

  // 그날 표시한 기록의 시각(하루 중 분).
  final prefix = '${Medicine.recordKey(date, 0, 0).split('_').first}_';
  final recorded = <int>{};
  for (final record in medicine.takenRecords) {
    if (!record.startsWith(prefix)) continue;
    final parts = record.substring(prefix.length).split(':');
    if (parts.length != 2) continue;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) continue;
    recorded.add(hour * 60 + minute);
  }

  // 지금 설정으로 본 그날의 예정.
  final created = medicine.createdAt;
  final createdDay = DateTime(created.year, created.month, created.day);
  final scheduled = <int>{};
  if (!date.isBefore(createdDay) && medicine.isOnWeekday(date.weekday)) {
    final createdMinute = created.hour * 60 + created.minute;
    for (final time in medicine.times) {
      final minuteOfDay = time.hour * 60 + time.minute;
      // 등록한 날, 등록하기 전에 지나간 시각은 예정이 아니었다.
      if (date == createdDay && minuteOfDay < createdMinute) continue;
      scheduled.add(minuteOfDay);
    }
  }

  final taken = recorded.toList()..sort();
  final missing = scheduled.difference(recorded).toList()..sort();
  // 예정에 없던 시각의 기록 한 건마다 「기록 없음」 한 건을 뺀다(이른 것부터).
  final moved = recorded.difference(scheduled).length;
  final stillMissing = missing.skip(moved);

  return [
    for (final minuteOfDay in taken) dose(minuteOfDay, taken: true),
    for (final minuteOfDay in stillMissing) dose(minuteOfDay, taken: false),
  ];
}
