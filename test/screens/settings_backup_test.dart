import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/settings_screen.dart';
import 'package:yakmukja/services/backup_file_gateway.dart';
import 'package:yakmukja/services/medicine_backup.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

import '../support/fake_notification_center.dart';
import '../support/memory_medicine_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box<Medicine> box;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yak_backup_ui_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  setUp(() async {
    await box.clear();
    NotificationService.resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.2.1',
      buildNumber: '17',
      buildSignature: '',
    );
  });

  tearDownAll(() async {
    await box.close();
    await dir.delete(recursive: true);
  });

  Medicine pill(
    String name, {
    int hour = 8,
    int minute = 0,
    DateTime? deletedAt,
    List<String> takenRecords = const [],
  }) {
    return Medicine(
      name: name,
      dosage: '1알',
      times: [DoseTime(hour: hour, minute: minute)],
      memo: '',
      createdAt: DateTime(2026, 1, 2, 3, 4, 5),
      takenRecords: [...takenRecords],
      deletedAt: deletedAt,
    );
  }

  Future<void> pumpSettings(
    WidgetTester tester, {
    BackupFileGateway? files,
    Box<Medicine>? medicineBox,
    Size size = const Size(402, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SettingsScreen(backupFiles: files, medicineBox: medicineBox),
      ),
    );
    await tester.pump();
  }

  testWidgets('휴지통 아래에 백업 두 줄과 안내가 보인다', (tester) async {
    await pumpSettings(tester);

    expect(find.text('약 목록 백업'), findsOneWidget);
    expect(find.text('백업에서 복원'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_backup_restore_rounded), findsOneWidget);
    expect(
      find.text('백업 파일에는 약 이름과 복용 기록이 들어 있어요. 믿을 수 있는 곳에 보관해 주세요.'),
      findsOneWidget,
    );
    expect(find.text('백업'), findsOneWidget);

    await tester.ensureVisible(find.text('휴지통'));
    await tester.ensureVisible(find.text('약 목록 백업'));
    expect(
      tester.getTopLeft(find.text('약 목록 백업')).dy,
      greaterThan(tester.getTopLeft(find.text('휴지통')).dy),
    );
    expect(
      tester.getTopLeft(find.text('백업에서 복원')).dy,
      greaterThan(tester.getTopLeft(find.text('약 목록 백업')).dy),
    );
  });

  testWidgets('약이 없으면 파일을 만들지 않고 안내만 보여 준다', (tester) async {
    final files = _FakeBackupFiles();
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('약 목록 백업'));
    await tester.tap(find.text('약 목록 백업'));
    await tester.pump();

    expect(find.text('백업할 약이 없어요'), findsOneWidget);
    expect(files.shareCount, 0);
  });

  testWidgets('백업을 누르면 공유가 한 번 열리고 파일 이름이 형식에 맞다', (tester) async {
    await box.add(pill('혈압약', takenRecords: ['2026-01-02_08:00']));
    await box.add(pill('버린약', hour: 21, deletedAt: DateTime(2026, 11, 1, 9)));
    final files = _FakeBackupFiles();
    await pumpSettings(tester, files: files);

    final before = DateTime.now();
    await tester.ensureVisible(find.text('약 목록 백업'));
    await tester.tap(find.text('약 목록 백업'));
    await tester.pump();
    final after = DateTime.now();

    expect(files.shareCount, 1);
    expect(files.sharedName, matches(_backupNamePattern));
    final stamped = _stampOf(files.sharedName!);
    expect(
      stamped.isBefore(before.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    expect(stamped.isAfter(after.add(const Duration(minutes: 1))), isFalse);

    final decoded = MedicineBackup.decode(files.sharedBytes!);
    expect(decoded.medicines.map((m) => m.name).toList(), ['혈압약', '버린약']);
    expect(decoded.medicines.first.takenRecords, ['2026-01-02_08:00']);
    expect(decoded.trashCount, 1);
    final jsonText = String.fromCharCodes(files.sharedBytes!);
    expect(
      jsonText.contains('"appVersion": "1.2.1+17"') ||
          jsonText.contains('"appVersion":"1.2.1+17"'),
      isTrue,
    );
    expect(find.text('백업할 약이 없어요'), findsNothing);
  });

  testWidgets('복원 확인에서 취소하면 약 상자가 그대로다', (tester) async {
    await box.add(pill('혈압약', hour: 9));
    final files = _FakeBackupFiles(
      pickBytes: MedicineBackup.encode(
        [pill('비타민', hour: 7)],
        now: DateTime(2026, 11, 12, 10),
        appVersion: '1.2.1+17',
      ),
    );
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('백업에서 복원'));
    await tester.tap(find.text('백업에서 복원'));
    await tester.pumpAndSettle();

    expect(find.text('백업에서 복원할까요?'), findsOneWidget);
    expect(find.text('백업 파일의 약 1개로 바꿔요. 지금 등록된 약 1개는 지워져요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(box.values.map((m) => m.name).toList(), ['혈압약']);
    expect(find.text('약 1개를 복원했어요'), findsNothing);
  });

  testWidgets('등록된 약이 없으면 지운다는 문장을 빼는 확인 창을 보여 준다', (tester) async {
    final files = _FakeBackupFiles(
      pickBytes: MedicineBackup.encode(
        [pill('비타민')],
        now: DateTime(2026, 11, 12, 10),
        appVersion: '1.2.1+17',
      ),
    );
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('백업에서 복원'));
    await tester.tap(find.text('백업에서 복원'));
    await tester.pumpAndSettle();

    expect(find.text('백업 파일의 약 1개로 바꿔요.'), findsOneWidget);
    expect(find.textContaining('지워져요'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(box.isEmpty, isTrue);
  });

  testWidgets('복원하면 상자가 백업으로 바뀌고 알림을 다시 맞춘다', (tester) async {
    tester.view.physicalSize = const Size(402, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final center = FakeNotificationCenter()..install(TargetPlatform.android);
    addTearDown(center.uninstall);
    try {
      await tester.runAsync(() async {
        await box.add(pill('혈압약', hour: 9));
        await NotificationService.init();
        await NotificationService.syncAll(box.values);
      });
      expect(center.alarms, ['매일 09:00 드실 약이 있어요.']);

      final files = _FakeBackupFiles(
        pickBytes: MedicineBackup.encode(
          [
            pill('비타민', hour: 8, takenRecords: ['2026-01-02_08:00']),
            pill('버린약', hour: 22, deletedAt: DateTime(2026, 11, 1)),
          ],
          now: DateTime(2026, 11, 12, 10),
          appVersion: '1.2.1+17',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SettingsScreen(backupFiles: files),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('백업에서 복원'));
      final openRestore = tester.widget<InkWell>(
        find.ancestor(of: find.text('백업에서 복원'), matching: find.byType(InkWell)),
      );
      // 알림 플러그인 응답은 진짜 시계에서만 돌아온다. 복원 함수를 그 시계에서 시작한다.
      await tester.runAsync(() async {
        openRestore.onTap!.call();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('백업 파일의 약 1개로 바꿔요. 지금 등록된 약 1개는 지워져요.'), findsOneWidget);

      final restore = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '복원'),
      );
      await tester.runAsync(() async {
        restore.onPressed!.call();
        for (var i = 0; center.alarms.join() != '매일 08:00 드실 약이 있어요.'; i++) {
          if (i == 300) {
            fail('알림이 비타민 시각으로 바뀌지 않았다. 알림=${center.alarms}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(box.values.map((m) => m.name).toList(), ['비타민', '버린약']);
      expect(box.values.first.takenRecords, ['2026-01-02_08:00']);
      expect(box.values.last.isInTrash, isTrue);
      expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
      expect(find.text('약 1개를 복원했어요'), findsOneWidget);
    } finally {
      center.uninstall();
    }
  });

  testWidgets('파일 고르기를 닫으면 아무 글도 띄우지 않는다', (tester) async {
    await box.add(pill('혈압약'));
    final files = _FakeBackupFiles(cancelPick: true);
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('백업에서 복원'));
    await tester.tap(find.text('백업에서 복원'));
    await tester.pumpAndSettle();

    expect(find.text('백업에서 복원할까요?'), findsNothing);
    expect(find.text('백업 파일을 읽을 수 없어요'), findsNothing);
    expect(box.values.single.name, '혈압약');
  });

  testWidgets('거절된 파일은 상자를 그대로 두고 이유를 보여 준다', (tester) async {
    await box.add(pill('혈압약'));
    final files = _FakeBackupFiles(
      pickBytes: Uint8List.fromList('{"format":"nope"}'.codeUnits),
    );
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('백업에서 복원'));
    await tester.tap(find.text('백업에서 복원'));
    await tester.pumpAndSettle();

    expect(find.text('약먹자 백업 파일이 아니에요'), findsOneWidget);
    expect(find.text('백업에서 복원할까요?'), findsNothing);
    expect(box.values.single.name, '혈압약');
  });

  testWidgets('빈 백업은 한 글자도 반영하지 않고 빈 파일 이유를 보여 준다', (tester) async {
    await box.add(pill('혈압약'));
    final files = _FakeBackupFiles(
      pickBytes: MedicineBackup.encode(
        <Medicine>[],
        now: DateTime(2026, 11, 12, 10),
        appVersion: '1.2.1+17',
      ),
    );
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('백업에서 복원'));
    await tester.tap(find.text('백업에서 복원'));
    await tester.pumpAndSettle();

    expect(find.text('백업 파일에 약이 없어요'), findsOneWidget);
    expect(box.values.single.name, '혈압약');
  });

  testWidgets('저장이 실패하면 약 목록을 되돌리고 실패 안내를 보여 준다', (tester) async {
    final memory = MemoryMedicineBox([
      pill('혈압약', takenRecords: ['2026-01-02_08:00']),
    ]);
    memory.throwOnAddAll = StateError('disk');
    final files = _FakeBackupFiles(
      pickBytes: MedicineBackup.encode(
        [pill('비타민')],
        now: DateTime(2026, 11, 12, 10),
        appVersion: '1.2.1+17',
      ),
    );
    await pumpSettings(tester, files: files, medicineBox: memory);

    await tester.ensureVisible(find.text('백업에서 복원'));
    await tester.tap(find.text('백업에서 복원'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '복원'));
    await tester.pumpAndSettle();

    expect(find.text('복원하지 못했어요. 약 목록은 그대로예요'), findsOneWidget);
    expect(memory.values.single.name, '혈압약');
    expect(memory.values.single.takenRecords, ['2026-01-02_08:00']);
    expect(find.textContaining('복원했어요'), findsNothing);
  });
}

final _backupNamePattern = RegExp(r'^yakmukja-backup-\d{8}-\d{4}\.json$');

DateTime _stampOf(String name) {
  final match = _backupNamePattern.firstMatch(name)!;
  final digits = match.group(0)!;
  final date = RegExp(
    r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})',
  ).firstMatch(digits)!;
  return DateTime(
    int.parse(date.group(1)!),
    int.parse(date.group(2)!),
    int.parse(date.group(3)!),
    int.parse(date.group(4)!),
    int.parse(date.group(5)!),
  );
}

class _FakeBackupFiles implements BackupFileGateway {
  _FakeBackupFiles({this.pickBytes, this.cancelPick = false});

  final Uint8List? pickBytes;
  final bool cancelPick;
  int shareCount = 0;
  Uint8List? sharedBytes;
  String? sharedName;

  @override
  Future<Uint8List?> pick() async {
    if (cancelPick) return null;
    return pickBytes;
  }

  @override
  Future<void> share(Uint8List bytes, String fileName) async {
    shareCount += 1;
    sharedBytes = Uint8List.fromList(bytes);
    sharedName = fileName;
  }
}
