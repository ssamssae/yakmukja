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
}

@HiveType(typeId: 1)
class DoseTime {
  @HiveField(0)
  int hour;

  @HiveField(1)
  int minute;

  DoseTime({required this.hour, required this.minute});

  String format() {
    String period;
    if (hour < 5) {
      period = '밤';
    } else if (hour < 9) {
      period = '아침';
    } else if (hour < 12) {
      period = '오전';
    } else if (hour < 14) {
      period = '낮';
    } else if (hour < 18) {
      period = '오후';
    } else {
      period = '저녁';
    }
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    return '$period $h:$m';
  }
}
