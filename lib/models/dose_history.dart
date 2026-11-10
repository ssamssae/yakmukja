import 'medicine.dart';

/// 지난 기록으로 보여 주는 날 수(어제부터 거꾸로). 복용 기록 정리와 같은
/// [doseRecordKeepDays]를 쓴다. (T-261110-039)
const int doseHistoryDays = doseRecordKeepDays;

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
/// - 예정에 없던 시각의 기록은 가장 가까운 남은 현재 시각과 짝짓고, 그 칸의
///   「기록 없음」을 뺀다. 시간을 옮긴 약을 두 줄로 세지 않기 위해서다.
/// - 등록한 날의 이른 시각 제외는 그 짝짓기 다음에 적용한다.
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

  // 지금 설정으로 본 그날의 시각. 등록한 날의 이른 시각도 일단 넣는다.
  // 그 시각을 먼저 빼면, 이른 시각 체크가 「옮긴 기록」으로 세어져
  // 등록 뒤의 진짜 놓침을 지운다.
  final created = medicine.createdAt;
  final createdDay = DateTime(created.year, created.month, created.day);
  final createdMinute = created.hour * 60 + created.minute;
  final current = <int>{
    if (!date.isBefore(createdDay) && medicine.isOnWeekday(date.weekday))
      for (final time in medicine.times) time.hour * 60 + time.minute,
  };

  // 예정에 없던 시각의 기록은 가장 가까운 남은 현재 시각과 짝짓는다.
  // 거리가 같으면 더 이른 시각과 짝짓는다.
  final unmatched = current.difference(recorded).toList()..sort();
  for (final record in recorded.difference(current).toList()..sort()) {
    if (unmatched.isEmpty) break;
    var best = 0;
    for (var i = 1; i < unmatched.length; i++) {
      final closer =
          (unmatched[i] - record).abs() < (unmatched[best] - record).abs();
      if (closer) best = i;
    }
    unmatched.removeAt(best);
  }
  final stillMissing = unmatched.where(
    (minuteOfDay) => !(date == createdDay && minuteOfDay < createdMinute),
  );

  final taken = recorded.toList()..sort();

  return [
    for (final minuteOfDay in taken) dose(minuteOfDay, taken: true),
    for (final minuteOfDay in stillMissing) dose(minuteOfDay, taken: false),
  ];
}
