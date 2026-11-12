import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/medicine_backup.dart';

import '../support/memory_medicine_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box<Medicine> hiveBox;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yak_backup_svc_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    hiveBox = await Hive.openBox<Medicine>(
      medicineBoxName,
      bytes: Uint8List(0),
    );
  });

  tearDown(() async {
    await hiveBox.clear();
  });

  tearDownAll(() async {
    await hiveBox.close();
    await dir.delete(recursive: true);
  });

  Medicine sample({
    String name = '혈압약',
    String dosage = '1알',
    String memo = '식후',
    List<DoseTime>? times,
    List<int>? weekdays,
    DateTime? createdAt,
    DateTime? endDate,
    DateTime? deletedAt,
    List<String> takenRecords = const ['2026-01-02_08:00', '2026-01-03_21:30'],
  }) {
    return Medicine(
      name: name,
      dosage: dosage,
      times:
          times ??
          [DoseTime(hour: 8, minute: 0), DoseTime(hour: 21, minute: 30)],
      memo: memo,
      createdAt: createdAt ?? DateTime(2026, 1, 2, 3, 4, 5),
      takenRecords: [...takenRecords],
      deletedAt: deletedAt,
      weekdays: weekdays,
      endDate: endDate,
    );
  }

  void expectSameMedicine(Medicine actual, Medicine expected) {
    expect(actual.name, expected.name);
    expect(actual.dosage, expected.dosage);
    expect(actual.memo, expected.memo);
    expect(
      [
        for (final time in actual.times) [time.hour, time.minute],
      ],
      [
        for (final time in expected.times) [time.hour, time.minute],
      ],
    );
    expect(actual.weekdays, expected.activeWeekdays);
    expect(actual.createdAt, expected.createdAt);
    expect(actual.endDate, expected.endDate);
    expect(actual.deletedAt, expected.deletedAt);
    expect(actual.takenRecords, expected.takenRecords);
  }

  test('내보낸 파일을 다시 읽으면 휴지통·끝나는 날·요일·복용 기록이 같다', () {
    final active = sample(weekdays: [1, 3, 5], endDate: DateTime(2026, 12, 31));
    final trashed = sample(
      name: '비타민',
      dosage: '',
      memo: '',
      times: [DoseTime(hour: 7, minute: 15)],
      weekdays: const [],
      createdAt: DateTime.utc(2024, 5, 6, 7, 8, 9),
      deletedAt: DateTime(2026, 11, 1, 12, 0),
      takenRecords: const [],
    );
    final now = DateTime(2026, 11, 12, 15, 4);
    final bytes = MedicineBackup.encode(
      [active, trashed],
      now: now,
      appVersion: '1.2.1+17',
    );

    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    expect(json['format'], 'yakmukja-backup');
    expect(json['version'], 1);
    expect(json['exportedAt'], now.toIso8601String());
    expect(json['appVersion'], '1.2.1+17');
    expect(json.containsKey('adsRemoved'), isFalse);

    final decoded = MedicineBackup.decode(bytes);
    expect(decoded.medicineCount, 2);
    expect(decoded.trashCount, 1);
    expect(decoded.exportedAt, now);
    expect(decoded.medicines, hasLength(2));
    expectSameMedicine(decoded.medicines[0], active);
    expect(decoded.medicines[1].name, '비타민');
    expect(decoded.medicines[1].dosage, '');
    expect(decoded.medicines[1].memo, '');
    expect(decoded.medicines[1].weekdays, Medicine.allWeekdays);
    expect(decoded.medicines[1].deletedAt, trashed.deletedAt);
    expect(decoded.medicines[1].takenRecords, isEmpty);
    expect(decoded.medicines[1].createdAt, trashed.createdAt);
  });

  test('모르는 키는 무시하고 이름 앞뒤 공백은 뺀다', () {
    final bytes = _encodeJson({
      'format': 'yakmukja-backup',
      'version': 1,
      'exportedAt': '2026-11-12T10:00:00.000',
      'appVersion': '1.2.1+17',
      'future': {'keep': true},
      'medicines': [
        {..._medicine(), 'name': '  혈압약  ', 'color': 'red'},
      ],
    });

    final decoded = MedicineBackup.decode(bytes);
    expect(decoded.medicines.single.name, '혈압약');
    expect(decoded.exportedAt, DateTime(2026, 11, 12, 10));
  });

  test('없는 복용량·메모·요일·복용 기록은 빈 값과 매일로 읽는다', () {
    final medicine = _medicine()
      ..remove('dosage')
      ..remove('memo')
      ..remove('weekdays')
      ..remove('takenRecords')
      ..remove('endDate')
      ..remove('deletedAt');
    final decoded = MedicineBackup.decode(_file(medicines: [medicine]));
    final restored = decoded.medicines.single;
    expect(restored.dosage, '');
    expect(restored.memo, '');
    expect(restored.weekdays, Medicine.allWeekdays);
    expect(restored.takenRecords, isEmpty);
    expect(restored.endDate, isNull);
    expect(restored.deletedAt, isNull);
  });

  test('2MB 를 넘는 파일은 거절한다', () {
    _expectReject(Uint8List(medicineBackupMaxBytes + 1), '백업 파일을 읽을 수 없어요');
  });

  test('JSON 이 아니면 거절한다', () {
    _expectReject(utf8.encode('{'), '백업 파일을 읽을 수 없어요');
  });

  test('맨 위가 객체가 아니면 거절한다', () {
    _expectReject(utf8.encode('[1]'), '백업 파일을 읽을 수 없어요');
  });

  test('약먹자 백업이 아니면 거절한다', () {
    _expectReject(_file(format: 'other-backup'), '약먹자 백업 파일이 아니에요');
  });

  test('더 새로운 버전이면 거절한다', () {
    _expectReject(_file(version: 2), '더 새로운 약먹자에서 만든 백업이에요. 앱을 업데이트해 주세요');
  });

  test('약이 목록이 아니면 거절한다', () {
    _expectReject(
      _encodeJson({
        'format': 'yakmukja-backup',
        'version': 1,
        'exportedAt': '2026-11-12T10:00:00.000',
        'medicines': {'name': '혈압약'},
      }),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('약이 500개를 넘으면 거절한다', () {
    _expectReject(
      _file(medicines: [for (var i = 0; i < 501; i++) _medicine()]),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('약이 없으면 거절한다', () {
    _expectReject(_file(medicines: const []), '백업 파일에 약이 없어요');
  });

  test('약 이름이 비었거나 100자를 넘으면 거절한다', () {
    _expectReject(
      _file(medicines: [_medicine(name: '   ')]),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(medicines: [_medicine(name: '가' * 101)]),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('복용량·메모가 글이 아니거나 500자를 넘으면 거절한다', () {
    _expectReject(_file(medicines: [_medicine(dosage: 1)]), '백업 파일을 읽을 수 없어요');
    _expectReject(
      _file(medicines: [_medicine(memo: '가' * 501)]),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('복용 시각이 없거나 24개를 넘거나 시·분이 범위 밖이면 거절한다', () {
    _expectReject(
      _file(medicines: [_medicine(times: const [])]),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(
        medicines: [
          _medicine(
            times: [
              for (var hour = 0; hour < 25; hour++) {'hour': 0, 'minute': 0},
            ],
          ),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(
        medicines: [
          _medicine(
            times: [
              {'hour': 24, 'minute': 0},
            ],
          ),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(
        medicines: [
          _medicine(
            times: [
              {'hour': 8, 'minute': 60},
            ],
          ),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(
        medicines: [
          _medicine(
            times: [
              {'hour': 8.5, 'minute': 0},
            ],
          ),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('요일이 1~7 의 중복 없는 목록이 아니면 거절한다', () {
    _expectReject(
      _file(
        medicines: [
          _medicine(weekdays: [1, 1]),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(
        medicines: [
          _medicine(weekdays: [0, 1]),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('만든 시각·끝나는 날·휴지통 시각을 읽을 수 없으면 거절한다', () {
    _expectReject(
      _file(medicines: [_medicine(createdAt: '어제')]),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(medicines: [_medicine(endDate: '2026-13-01')]),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(medicines: [_medicine(deletedAt: '곧')]),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('복용 기록 형식이 아니거나 5000개를 넘으면 거절한다', () {
    _expectReject(
      _file(
        medicines: [
          _medicine(takenRecords: ['2026-01-02 08:00']),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
    _expectReject(
      _file(
        medicines: [
          _medicine(
            takenRecords: [for (var i = 0; i < 5001; i++) '2026-01-02_08:00'],
          ),
        ],
      ),
      '백업 파일을 읽을 수 없어요',
    );
  });

  test('거절된 파일은 약 목록을 돌려주지 않는다', () {
    expect(
      () => MedicineBackup.decode(_file(medicines: const [])),
      throwsA(isA<MedicineBackupException>()),
    );
  });

  test('restore 는 상자 전체를 백업 내용으로 바꾼다', () async {
    await hiveBox.add(sample(name: '옛약'));
    await hiveBox.add(sample(name: '휴지', deletedAt: DateTime(2026, 11, 1)));
    final incoming = [
      sample(name: '새약', takenRecords: const ['2026-02-01_09:00']),
    ];

    await MedicineBackup.restore(hiveBox, incoming);

    expect(hiveBox.values.map((m) => m.name).toList(), ['새약']);
    expect(hiveBox.values.single.takenRecords, ['2026-02-01_09:00']);
  });

  test('restore 가 쓰는 도중 실패하면 복원 전 약으로 되돌린다', () async {
    final original = sample(name: '혈압약');
    final box = MemoryMedicineBox([original]);
    box.throwOnAddAll = StateError('disk');

    await expectLater(
      MedicineBackup.restore(box, [sample(name: '새약')]),
      throwsA(isA<StateError>()),
    );

    original.name = '바뀜';
    original.takenRecords.clear();
    expect(box.values.single.name, '혈압약');
    expect(box.values.single.takenRecords, [
      '2026-01-02_08:00',
      '2026-01-03_21:30',
    ]);
    expect(box.values.single.dosage, '1알');
  });
}

Map<String, Object?> _medicine({
  Object? name = '혈압약',
  Object? dosage = '1알',
  Object? memo = '',
  Object? times = const [
    {'hour': 8, 'minute': 0},
  ],
  Object? weekdays = const [1, 2, 3, 4, 5, 6, 7],
  Object? createdAt = '2026-01-02T03:04:05.000',
  Object? endDate,
  Object? deletedAt,
  Object? takenRecords = const <String>[],
}) {
  return {
    'name': name,
    'dosage': dosage,
    'memo': memo,
    'times': times,
    'weekdays': weekdays,
    'createdAt': createdAt,
    'endDate': endDate,
    'deletedAt': deletedAt,
    'takenRecords': takenRecords,
  };
}

Uint8List _file({
  String format = 'yakmukja-backup',
  Object? version = 1,
  List<Object?> medicines = const [],
}) {
  return _encodeJson({
    'format': format,
    'version': version,
    'exportedAt': '2026-11-12T10:00:00.000',
    'appVersion': '1.2.1+17',
    'medicines': medicines,
  });
}

Uint8List _encodeJson(Map<String, Object?> json) {
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

void _expectReject(List<int> bytes, String message) {
  expect(
    () => MedicineBackup.decode(bytes),
    throwsA(
      isA<MedicineBackupException>().having(
        (error) => error.message,
        'message',
        message,
      ),
    ),
  );
}
