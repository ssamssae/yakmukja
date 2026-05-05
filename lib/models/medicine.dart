import 'package:hive/hive.dart';

part 'medicine.g.dart';

@HiveType(typeId: 0)
class Medicine extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String dosage;

  @HiveField(2)
  List<DoseTime> times;

  @HiveField(3)
  String memo;

  @HiveField(4)
  DateTime createdAt;

  /// 복용 완료 기록 ("yyyy-MM-dd_HH:mm" 형식)
  @HiveField(5)
  List<String> takenRecords;

  Medicine({
    required this.name,
    required this.dosage,
    required this.times,
    required this.memo,
    required this.createdAt,
    List<String>? takenRecords,
  }) : takenRecords = takenRecords ?? [];

  String _todayKey(DoseTime t) {
    final now = DateTime.now();
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return '${d}_${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  bool isTaken(DoseTime t) => takenRecords.contains(_todayKey(t));

  void toggleTaken(DoseTime t) {
    final key = _todayKey(t);
    if (takenRecords.contains(key)) {
      takenRecords.remove(key);
    } else {
      takenRecords.add(key);
    }
    save();
  }

  // takenRecords 는 "yyyy-MM-dd_HH:mm" 형식. 30일 초과 레코드를 제거한다.
  // 앱 기동 시 한 번 호출하면 무한 누적을 막는다.
  void pruneOldRecords({int keepDays = 30}) {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    final cutoffStr =
        '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
    final pruned = takenRecords.where((r) => r.compareTo(cutoffStr) >= 0).toList();
    if (pruned.length != takenRecords.length) {
      takenRecords = pruned;
      save();
    }
  }
}

@HiveType(typeId: 1)
class DoseTime {
  @HiveField(0)
  int hour;

  @HiveField(1)
  int minute;

  DoseTime({required this.hour, required this.minute});

  String get periodLabel {
    if (hour < 5) return '밤';
    if (hour < 9) return '아침';
    if (hour < 12) return '오전';
    if (hour < 14) return '낮';
    if (hour < 18) return '오후';
    return '저녁';
  }

  String format() {
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    return '$periodLabel $h:$m';
  }
}
