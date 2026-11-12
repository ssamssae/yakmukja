import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 백업 파일을 공유 창으로 보내고, 고른 파일의 바이트를 돌려준다.
/// 사용자가 창을 닫으면 [pick] 은 null 이다.
abstract class BackupFileGateway {
  const BackupFileGateway();

  Future<void> share(Uint8List bytes, String fileName);

  Future<Uint8List?> pick();
}

/// [share_plus] 로 공유하고 [file_picker] 로 고른다.
class PlatformBackupFileGateway extends BackupFileGateway {
  const PlatformBackupFileGateway();

  @override
  Future<void> share(Uint8List bytes, String fileName) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json', name: fileName)],
        fileNameOverrides: [fileName],
        sharePositionOrigin: _shareOrigin(),
      ),
    );
  }

  @override
  Future<Uint8List?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null) return Uint8List(0);
    return bytes;
  }
}

/// iPad 공유 창은 출발 칸이 필요하다. 화면 한가운데의 작은 칸을 쓴다.
Rect _shareOrigin() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return const Rect.fromLTWH(0, 0, 2, 2);
  final view = views.first;
  final width = view.physicalSize.width / view.devicePixelRatio;
  final height = view.physicalSize.height / view.devicePixelRatio;
  return Rect.fromCenter(
    center: Offset(width / 2, height / 2),
    width: 2,
    height: 2,
  );
}
