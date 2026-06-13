import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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
}
