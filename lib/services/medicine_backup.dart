import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

import '../models/medicine.dart';

/// 백업 파일의 최대 크기. 2MB 를 넘으면 읽지 않는다.
const int medicineBackupMaxBytes = 2 * 1024 * 1024;

const int _backupVersion = 1;
const int _maxMedicines = 500;
const int _maxTakenRecords = 5000;
const int _maxNameLength = 100;
const int _maxNoteLength = 500;
const int _maxTimes = 24;

final RegExp _takenRecordPattern = RegExp(r'^\d{4}-\d{2}-\d{2}_\d{2}:\d{2}$');
final RegExp _endDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

/// 백업 파일을 거절하는 이유.
enum MedicineBackupProblem { unreadable, notYakmukja, newerVersion, empty }

/// 백업 파일 검사에 걸렸을 때 던진다. 약 목록은 바꾸지 않는다.
class MedicineBackupException implements Exception {
  MedicineBackupException(this.problem);

  final MedicineBackupProblem problem;

  String get message {
    switch (problem) {
      case MedicineBackupProblem.unreadable:
        return '백업 파일을 읽을 수 없어요';
      case MedicineBackupProblem.notYakmukja:
        return '약먹자 백업 파일이 아니에요';
      case MedicineBackupProblem.newerVersion:
        return '더 새로운 약먹자에서 만든 백업이에요. 앱을 업데이트해 주세요';
      case MedicineBackupProblem.empty:
        return '백업 파일에 약이 없어요';
    }
  }

  @override
  String toString() => message;
}

/// 검사를 통과한 백업. [medicines] 는 아직 상자에 넣지 않은 새 약이다.
class MedicineBackupData {
  MedicineBackupData({required this.medicines, required this.exportedAt});

  final List<Medicine> medicines;
  final DateTime exportedAt;

  int get medicineCount => medicines.length;

  int get trashCount =>
      medicines.where((medicine) => medicine.isInTrash).length;
}

/// 약 목록을 파일로 바꾸고, 파일을 검사해 약 목록으로 되돌린다.
/// 화면과 공유·파일 플러그인을 모른다.
class MedicineBackup {
  const MedicineBackup._();

  static Uint8List encode(
    Iterable<Medicine> medicines, {
    required DateTime now,
    required String appVersion,
  }) {
    final json = <String, Object?>{
      'format': 'yakmukja-backup',
      'version': _backupVersion,
      'exportedAt': now.toIso8601String(),
      'appVersion': appVersion,
      'medicines': [for (final medicine in medicines) _medicineJson(medicine)],
    };
    return Uint8List.fromList(utf8.encode('${_jsonEncoder.convert(json)}\n'));
  }

  static MedicineBackupData decode(List<int> bytes) {
    if (bytes.length > medicineBackupMaxBytes) {
      throw MedicineBackupException(MedicineBackupProblem.unreadable);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw MedicineBackupException(MedicineBackupProblem.unreadable);
      }
      return _decodeMap(decoded.map((key, value) => MapEntry('$key', value)));
    } on MedicineBackupException {
      rethrow;
    } catch (_) {
      throw MedicineBackupException(MedicineBackupProblem.unreadable);
    }
  }

  /// 상자 전체를 [medicines] 로 바꾼다.
  /// 중간에 실패하면 바꾸기 전 내용으로 되돌리고 같은 오류를 다시 던진다.
  static Future<void> restore(
    Box<Medicine> box,
    List<Medicine> medicines,
  ) async {
    final snapshot = [for (final medicine in box.values) _copy(medicine)];
    try {
      await box.clear();
      await box.addAll(medicines);
    } catch (error, stack) {
      try {
        await box.clear();
        await box.addAll(snapshot);
      } catch (_) {
        Error.throwWithStackTrace(error, stack);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}

/// 공유 창에 넘길 파일 이름. `yakmukja-backup-YYYYMMDD-HHmm.json`.
String medicineBackupFileName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'yakmukja-backup-'
      '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}.json';
}

Map<String, Object?> _medicineJson(Medicine medicine) {
  final end = medicine.endDate;
  return {
    'name': medicine.name,
    'dosage': medicine.dosage,
    'memo': medicine.memo,
    'times': [
      for (final time in medicine.times)
        {'hour': time.hour, 'minute': time.minute},
    ],
    'weekdays': medicine.activeWeekdays,
    'createdAt': medicine.createdAt.toIso8601String(),
    'endDate': end == null ? null : _dateText(end),
    'deletedAt': medicine.deletedAt?.toIso8601String(),
    'takenRecords': [...medicine.takenRecords],
  };
}

MedicineBackupData _decodeMap(Map<String, Object?> json) {
  if (json['format'] != 'yakmukja-backup') {
    throw MedicineBackupException(MedicineBackupProblem.notYakmukja);
  }
  final version = json['version'];
  if (version is! num) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  if (version > _backupVersion) {
    throw MedicineBackupException(MedicineBackupProblem.newerVersion);
  }
  if (version != _backupVersion) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final exportedAt = json['exportedAt'];
  if (exportedAt is! String) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final parsedAt = DateTime.tryParse(exportedAt);
  if (parsedAt == null) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final rawMedicines = json['medicines'];
  if (rawMedicines is! List) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  if (rawMedicines.isEmpty) {
    throw MedicineBackupException(MedicineBackupProblem.empty);
  }
  if (rawMedicines.length > _maxMedicines) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return MedicineBackupData(
    medicines: [for (final raw in rawMedicines) _medicine(raw)],
    exportedAt: parsedAt,
  );
}

Medicine _medicine(Object? raw) {
  if (raw is! Map) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final json = raw.map((key, value) => MapEntry('$key', value));
  return Medicine(
    name: _name(json['name']),
    dosage: _note(json['dosage']),
    memo: _note(json['memo']),
    times: _times(json['times']),
    createdAt: _requiredTime(json['createdAt']),
    takenRecords: _takenRecords(json['takenRecords']),
    deletedAt: _optionalTime(json['deletedAt']),
    weekdays: _weekdays(json['weekdays']),
    endDate: _endDate(json['endDate']),
  );
}

String _name(Object? value) {
  if (value is! String) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final trimmed = value.trim();
  final length = trimmed.runes.length;
  if (length < 1 || length > _maxNameLength) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return trimmed;
}

String _note(Object? value) {
  if (value == null) return '';
  if (value is! String || value.runes.length > _maxNoteLength) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return value;
}

List<DoseTime> _times(Object? value) {
  if (value is! List || value.isEmpty || value.length > _maxTimes) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return [for (final item in value) _time(item)];
}

DoseTime _time(Object? value) {
  if (value is! Map) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final json = value.map((key, item) => MapEntry('$key', item));
  final hour = json['hour'];
  final minute = json['minute'];
  if (hour is! int || minute is! int) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return DoseTime(hour: hour, minute: minute);
}

List<int> _weekdays(Object? value) {
  if (value == null) return List<int>.from(Medicine.allWeekdays);
  if (value is! List) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  if (value.isEmpty) return List<int>.from(Medicine.allWeekdays);
  final days = <int>[];
  final seen = <int>{};
  for (final item in value) {
    if (item is! int || item < 1 || item > 7 || !seen.add(item)) {
      throw MedicineBackupException(MedicineBackupProblem.unreadable);
    }
    days.add(item);
  }
  return days;
}

DateTime _requiredTime(Object? value) {
  final parsed = _optionalTime(value);
  if (parsed == null) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return parsed;
}

DateTime? _optionalTime(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return parsed;
}

DateTime? _endDate(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final match = _endDatePattern.firstMatch(value);
  if (match == null) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  return date;
}

List<String> _takenRecords(Object? value) {
  if (value == null) return [];
  if (value is! List || value.length > _maxTakenRecords) {
    throw MedicineBackupException(MedicineBackupProblem.unreadable);
  }
  final records = <String>[];
  for (final item in value) {
    if (item is! String || !_takenRecordPattern.hasMatch(item)) {
      throw MedicineBackupException(MedicineBackupProblem.unreadable);
    }
    records.add(item);
  }
  return records;
}

Medicine _copy(Medicine medicine) {
  return Medicine(
    name: medicine.name,
    dosage: medicine.dosage,
    times: [
      for (final time in medicine.times)
        DoseTime(hour: time.hour, minute: time.minute),
    ],
    memo: medicine.memo,
    createdAt: medicine.createdAt,
    takenRecords: [...medicine.takenRecords],
    deletedAt: medicine.deletedAt,
    weekdays: [...medicine.weekdays],
    endDate: medicine.endDate,
  );
}

String _dateText(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
