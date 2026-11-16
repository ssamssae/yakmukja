import 'package:flutter/services.dart';

import 'medicine_backup.dart';

/// iCloud 에 있는 약먹자 백업 파일 하나.
class ICloudBackupFile {
  const ICloudBackupFile({
    required this.name,
    required this.modified,
    required this.size,
  });

  final String name;
  final DateTime modified;
  final int size;

  /// 고르기 창에 보여 줄 날짜와 시각. 파일 이름 속 시각을 쓴다(`2026-11-16 19:05`).
  String get label {
    final match = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})').firstMatch(name);
    if (match == null) return name;
    return '${match[1]}-${match[2]}-${match[3]} ${match[4]}:${match[5]}';
  }
}

/// 아이폰 기본 백업 — 로그인 없는 iCloud (T-261116-043, 한줄일기 방식).
///
/// 기기에 로그인된 Apple 계정의 iCloud Drive 앱 폴더
/// (컨테이너 iCloud.com.ssamssae.yakmukja 의 Documents)에 백업 파일을 둔다.
/// 실제 파일 읽기·쓰기는 iOS 쪽 `YakmukjaICloudBackup`(AppDelegate.swift)이 한다.
class ICloudMedicineBackup {
  ICloudMedicineBackup({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yakmukja/icloud_backup');

  final MethodChannel _channel;

  /// iCloud 에 보관하는 백업 개수. 새 백업 뒤 더 오래된 것은 지운다.
  static const keep = 5;

  /// 이 기기가 iCloud 에 로그인돼 있고 iCloud Drive 를 쓸 수 있는지.
  Future<bool> isAvailable() async {
    try {
      final status = await _channel.invokeMapMethod<String, Object?>('status');
      return status?['available'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> upload(Uint8List bytes, {DateTime? now}) async {
    await _channel.invokeMethod<void>('save', {
      'name': medicineBackupFileName(now ?? DateTime.now()),
      'bytes': bytes,
    });
    try {
      await _prune();
    } catch (_) {
      // 새 백업은 이미 저장됐다. 오래된 백업 정리는 다음 백업 때 다시 한다.
    }
  }

  /// 최신 백업부터. 이름에 날짜가 들어 있어 이름순이 곧 시간순이다.
  Future<List<ICloudBackupFile>> list() async {
    final raw = await _channel.invokeListMethod<Object?>('list') ?? const [];
    final files = <ICloudBackupFile>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is! String || !isMedicineBackupFileName(name)) continue;
      final modified = item['modified'];
      final size = item['size'];
      files.add(
        ICloudBackupFile(
          name: name,
          modified: DateTime.fromMillisecondsSinceEpoch(
            modified is int ? modified : 0,
          ),
          size: size is int ? size : 0,
        ),
      );
    }
    files.sort((a, b) => b.name.compareTo(a.name));
    return files;
  }

  Future<Uint8List> download(String name) async {
    final bytes = await _channel.invokeMethod<Uint8List>('read', {
      'name': name,
    });
    if (bytes == null) {
      throw MedicineBackupException(MedicineBackupProblem.unreadable);
    }
    return bytes;
  }

  Future<void> _prune() async {
    final files = await list();
    for (final old in files.skip(keep)) {
      await _channel.invokeMethod<void>('delete', {'name': old.name});
    }
  }
}
