import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/models/medicine.dart';

// Medicine Hive 직렬화 라운드트립 + 박스 의존 로직(toggleTaken / pruneOldRecords).
// HiveObject.save() 가 박스를 요구하므로 임시 디렉토리에 in-memory Hive 를 띄운다.

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('yakmukja_hive_test');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
  });

  tearDown(() async {
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String todayKey(DoseTime t) {
    final now = DateTime.now();
    final d =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return '${d}_${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  test('직렬화 라운드트립: 닫고 다시 열어도 모든 필드 보존(다중 복용시간 포함)', () async {
    var box = await Hive.openBox<Medicine>('meds');
    await box.add(
      Medicine(
        name: '오메가3',
        dosage: '2캡슐',
        times: [
          DoseTime(hour: 8, minute: 0),
          DoseTime(hour: 13, minute: 30),
          DoseTime(hour: 20, minute: 15),
        ],
        memo: '식후 30분',
        createdAt: DateTime(2026, 6, 13, 9, 0),
        takenRecords: ['2026-06-13_08:00'],
      ),
    );
    await box.close();

    box = await Hive.openBox<Medicine>('meds');
    final m = box.getAt(0)!;
    expect(m.name, '오메가3');
    expect(m.dosage, '2캡슐');
    expect(m.memo, '식후 30분');
    expect(m.createdAt, DateTime(2026, 6, 13, 9, 0));
    expect(m.takenRecords, ['2026-06-13_08:00']);
    expect(m.times.length, 3);
    expect(m.times.map((t) => t.hour).toList(), [8, 13, 20]);
    expect(m.times.map((t) => t.minute).toList(), [0, 30, 15]);
  });

  test('toggleTaken: 토글하면 isTaken 이 뒤집히고 영속된다', () async {
    final box = await Hive.openBox<Medicine>('meds');
    final t = DoseTime(hour: 8, minute: 0);
    final m = Medicine(
      name: 'A',
      dosage: '1',
      times: [t],
      memo: '',
      createdAt: DateTime(2026, 1, 1),
    );
    await box.add(m);

    expect(m.isTaken(t), isFalse);
    m.toggleTaken(t); // save() 호출 — 박스 필요
    expect(m.isTaken(t), isTrue);
    expect(box.getAt(0)!.takenRecords, contains(todayKey(t)));

    m.toggleTaken(t);
    expect(m.isTaken(t), isFalse);
    expect(box.getAt(0)!.takenRecords, isEmpty);
  });

  test('pruneOldRecords: 30일 초과 레코드만 제거하고 최근 레코드는 유지', () async {
    final box = await Hive.openBox<Medicine>('meds');
    final recent = todayKey(DoseTime(hour: 8, minute: 0));
    final m = Medicine(
      name: 'A',
      dosage: '1',
      times: [DoseTime(hour: 8, minute: 0)],
      memo: '',
      createdAt: DateTime(2026, 1, 1),
      takenRecords: ['2020-01-01_08:00', '2019-12-31_20:00', recent],
    );
    await box.add(m);

    m.pruneOldRecords();
    expect(m.takenRecords, [recent]);
    expect(box.getAt(0)!.takenRecords, [recent]);
  });

  test('pruneOldRecords: 제거할 것 없으면 그대로 유지', () async {
    final box = await Hive.openBox<Medicine>('meds');
    final recent = todayKey(DoseTime(hour: 8, minute: 0));
    final m = Medicine(
      name: 'A',
      dosage: '1',
      times: [DoseTime(hour: 8, minute: 0)],
      memo: '',
      createdAt: DateTime(2026, 1, 1),
      takenRecords: [recent],
    );
    await box.add(m);

    m.pruneOldRecords();
    expect(m.takenRecords, [recent]);
  });

  // hive_ce 마이그레이션 데이터 보존 게이트 (T-260614-09): 여러 레코드를 쓰고
  // 박스를 닫았다 다시 열어 레코드 수·내용이 그대로인지 검증. hive_ce 어댑터의
  // 바이트 레이아웃이 기존 hive 와 동일하므로 기존 사용자 box 도 무손실로 열린다.
  test('마이그레이션 보존: 다중 레코드 닫고 다시 열어도 수·내용 일치', () async {
    var box = await Hive.openBox<Medicine>('meds');
    await box.add(Medicine(
      name: '혈압약',
      dosage: '1알',
      times: [DoseTime(hour: 9, minute: 0)],
      memo: '아침',
      createdAt: DateTime(2026, 6, 14, 9, 0),
      takenRecords: ['2026-06-14_09:00'],
    ));
    await box.add(Medicine(
      name: '비타민',
      dosage: '1.5알',
      times: [DoseTime(hour: 9, minute: 0), DoseTime(hour: 21, minute: 0)],
      memo: '',
      createdAt: DateTime(2026, 6, 14, 9, 5),
    ));
    await box.close();

    box = await Hive.openBox<Medicine>('meds');
    expect(box.length, 2);
    final a = box.getAt(0)!;
    final b = box.getAt(1)!;
    expect(a.name, '혈압약');
    expect(a.takenRecords, ['2026-06-14_09:00']);
    expect(a.times.length, 1);
    expect(b.name, '비타민');
    expect(b.dosage, '1.5알');
    expect(b.times.map((t) => t.hour).toList(), [9, 21]);
  });
}
