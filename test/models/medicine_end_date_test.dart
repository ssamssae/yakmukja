import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/models/medicine.dart';

/// 약의 「끝나는 날」 — 그날까지 먹고, 그 뒤로는 먹는 약이 아니다. (T-261110-042)
void main() {
  Medicine medicine({DateTime? endDate}) => Medicine(
    name: '항생제',
    dosage: '1알',
    times: [DoseTime(hour: 8, minute: 0)],
    memo: '',
    createdAt: DateTime(2026, 11, 1),
    endDate: endDate,
  );

  group('먹는 기간', () {
    test('끝나는 날을 정하지 않으면 언제나 먹는 약이다', () {
      final m = medicine();

      expect(m.endDate, isNull);
      expect(m.isActiveOn(DateTime(2026, 11, 10)), isTrue);
      expect(m.isActiveOn(DateTime(2099, 1, 1)), isTrue);
    });

    test('끝나는 날 당일 밤까지는 먹는 약이다', () {
      final m = medicine(endDate: DateTime(2026, 11, 20));

      expect(m.isActiveOn(DateTime(2026, 11, 19, 8, 0)), isTrue);
      expect(m.isActiveOn(DateTime(2026, 11, 20, 23, 59)), isTrue);
    });

    test('끝나는 날 다음 날부터는 먹는 약이 아니다', () {
      final m = medicine(endDate: DateTime(2026, 11, 20));

      expect(m.isActiveOn(DateTime(2026, 11, 21, 0, 0)), isFalse);
      expect(m.isActiveOn(DateTime(2026, 12, 1)), isFalse);
    });

    test('끝나는 날에 시각이 섞여 있어도 날짜로만 본다', () {
      final m = medicine(endDate: DateTime(2026, 11, 20, 9, 30));

      expect(m.isActiveOn(DateTime(2026, 11, 20, 23, 0)), isTrue);
      expect(m.isActiveOn(DateTime(2026, 11, 21, 1, 0)), isFalse);
    });
  });

  group('저장', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('yakmukja_end_date_test');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('끝나는 날은 닫고 다시 열어도 그대로다', () async {
      Hive.registerAdapter(MedicineAdapter(), override: true);
      Hive.registerAdapter(DoseTimeAdapter(), override: true);
      var box = await Hive.openBox<Medicine>('meds');
      await box.add(medicine(endDate: DateTime(2026, 11, 20)));
      await box.add(medicine());
      await box.close();

      box = await Hive.openBox<Medicine>('meds');

      expect(box.getAt(0)!.endDate, DateTime(2026, 11, 20));
      expect(box.getAt(1)!.endDate, isNull);
    });

    test('끝나는 날 칸이 없던 옛 데이터는 계속 먹는 약으로 읽힌다', () async {
      // 이 기능을 넣기 전의 저장 형식(칸 0~7)으로 쓴다.
      Hive.registerAdapter(_LegacyMedicineAdapter(), override: true);
      Hive.registerAdapter(DoseTimeAdapter(), override: true);
      var box = await Hive.openBox<Medicine>('meds');
      await box.add(
        Medicine(
          name: '혈압약',
          dosage: '1알',
          times: [DoseTime(hour: 8, minute: 0)],
          memo: '식후',
          createdAt: DateTime(2026, 10, 1),
          takenRecords: ['2026-11-09_08:00'],
          weekdays: [1, 3, 5],
        ),
      );
      await box.close();

      // 지금 판의 형식으로 읽는다.
      Hive.registerAdapter(MedicineAdapter(), override: true);
      box = await Hive.openBox<Medicine>('meds');
      final read = box.getAt(0)!;

      expect(read.endDate, isNull);
      expect(read.isActiveOn(DateTime(2099, 1, 1)), isTrue);
      expect(read.name, '혈압약');
      expect(read.memo, '식후');
      expect(read.takenRecords, ['2026-11-09_08:00']);
      expect(read.weekdays, [1, 3, 5]);
    });
  });
}

/// 「끝나는 날」을 넣기 전 판의 저장 형식. 칸 0~7 만 쓴다.
class _LegacyMedicineAdapter extends TypeAdapter<Medicine> {
  @override
  final typeId = 0;

  @override
  Medicine read(BinaryReader reader) => MedicineAdapter().read(reader);

  @override
  void write(BinaryWriter writer, Medicine obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.dosage)
      ..writeByte(2)
      ..write(obj.times)
      ..writeByte(3)
      ..write(obj.memo)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.takenRecords)
      ..writeByte(6)
      ..write(obj.deletedAt)
      ..writeByte(7)
      ..write(obj.weekdays);
  }
}
