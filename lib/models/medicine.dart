import 'package:hive_ce/hive.dart';

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

  /// 휴지통 보관 시각. null = 활성, 값 있으면 휴지통에 있음. (T-260614-12)
  @HiveField(6)
  DateTime? deletedAt;

  /// 복용 요일 (ISO 8601: 1=월 … 7=일). 기본 = 매일([1..7]).
  /// 기존(필드 추가 전) 저장 데이터는 이 필드가 비어/null 로 역직렬화되는데,
  /// 그 경우 "매일"로 간주한다(activeWeekdays 게터 참조).
  /// ⚠️ field 6 은 design-B(휴지통 deletedAt) 가 선점 → 충돌 회피로 7 사용.
  @HiveField(7)
  List<int> weekdays;

  Medicine({
    required this.name,
    required this.dosage,
    required this.times,
    required this.memo,
    required this.createdAt,
    List<String>? takenRecords,
    this.deletedAt,
    List<int>? weekdays,
  })  : takenRecords = takenRecords ?? [],
        weekdays = weekdays ?? const [1, 2, 3, 4, 5, 6, 7];

  /// 매일을 뜻하는 전체 요일 집합.
  static const allWeekdays = [1, 2, 3, 4, 5, 6, 7];

  /// 마이그레이션 안전 게터 — weekdays 가 비어있으면(구버전 데이터) "매일"로 본다.
  /// 알림/홈 필터는 항상 이 게터를 사용한다.
  List<int> get activeWeekdays =>
      weekdays.isEmpty ? allWeekdays : weekdays;

  /// 매일 복용 여부(전체 7요일 선택).
  bool get isDaily => activeWeekdays.length == 7;

  /// 지정한 ISO 요일(1=월 … 7=일)에 복용하는 약인지.
  bool isOnWeekday(int isoWeekday) => activeWeekdays.contains(isoWeekday);

  /// 요일 라벨 — 매일이면 "매일", 아니면 "월·수·금" 형태(월→일 순서).
  String get weekdayLabel {
    if (isDaily) return '매일';
    const names = ['월', '화', '수', '목', '금', '토', '일'];
    final sorted = [...activeWeekdays]..sort();
    return sorted.map((d) => names[d - 1]).join('·');
  }

  /// 휴지통 보관 기간 — 이 기간이 지나면 자동 영구삭제된다.
  static const trashRetention = Duration(days: 30);

  bool get isInTrash => deletedAt != null;

  /// 영구삭제까지 남은 시간 (음수면 이미 만료).
  Duration get timeUntilPurge {
    final d = deletedAt;
    if (d == null) return Duration.zero;
    return d.add(trashRetention).difference(DateTime.now());
  }

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
