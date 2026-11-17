import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/settings_screen.dart';
import 'package:yakmukja/services/backup_file_gateway.dart';
import 'package:yakmukja/services/icloud_medicine_backup.dart';
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
    ICloudMedicineBackup? icloud,
    TargetPlatform? platform,
    Size size = const Size(402, 1600),
    Locale locale = const Locale('ko'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light,
        home: SettingsScreen(
          backupFiles: files,
          medicineBox: medicineBox,
          icloud: icloud,
          platform: platform,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapFileAction(
    WidgetTester tester,
    String fileName,
    String action,
  ) async {
    final row = find.byKey(ValueKey('icloud-backup-$fileName'));
    await tester.ensureVisible(row);
    await tester.tap(
      find.descendant(
        of: row,
        matching: find.widgetWithText(TextButton, action),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('안드로이드는 휴지통 아래에 파일 백업 두 줄과 안내만 보인다', (tester) async {
    await pumpSettings(tester);

    expect(find.text('파일로 백업'), findsOneWidget);
    expect(find.text('파일에서 복원'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_backup_restore_rounded), findsOneWidget);
    expect(find.text(_androidFileNotice), findsOneWidget);
    expect(find.text('iCloud에 백업'), findsNothing);
    expect(find.text('iCloud에서 복원'), findsNothing);
    expect(find.text('아직 백업이 없어요'), findsNothing);
    expect(find.text('불러오는 중'), findsNothing);
    expect(find.text('백업'), findsOneWidget);

    await tester.ensureVisible(find.text('휴지통'));
    await tester.ensureVisible(find.text('파일로 백업'));
    expect(
      tester.getTopLeft(find.text('파일로 백업')).dy,
      greaterThan(tester.getTopLeft(find.text('휴지통')).dy),
    );
    expect(
      tester.getTopLeft(find.text('파일에서 복원')).dy,
      greaterThan(tester.getTopLeft(find.text('파일로 백업')).dy),
    );
  });

  testWidgets('약이 없으면 파일을 만들지 않고 안내만 보여 준다', (tester) async {
    final files = _FakeBackupFiles();
    await pumpSettings(tester, files: files);

    await tester.ensureVisible(find.text('파일로 백업'));
    await tester.tap(find.text('파일로 백업'));
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
    await tester.ensureVisible(find.text('파일로 백업'));
    await tester.tap(find.text('파일로 백업'));
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

    await tester.ensureVisible(find.text('파일에서 복원'));
    await tester.tap(find.text('파일에서 복원'));
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

    await tester.ensureVisible(find.text('파일에서 복원'));
    await tester.tap(find.text('파일에서 복원'));
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
      await tester.ensureVisible(find.text('파일에서 복원'));
      final openRestore = tester.widget<InkWell>(
        find.ancestor(of: find.text('파일에서 복원'), matching: find.byType(InkWell)),
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

    await tester.ensureVisible(find.text('파일에서 복원'));
    await tester.tap(find.text('파일에서 복원'));
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

    await tester.ensureVisible(find.text('파일에서 복원'));
    await tester.tap(find.text('파일에서 복원'));
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

    await tester.ensureVisible(find.text('파일에서 복원'));
    await tester.tap(find.text('파일에서 복원'));
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

    await tester.ensureVisible(find.text('파일에서 복원'));
    await tester.tap(find.text('파일에서 복원'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '복원'));
    await tester.pumpAndSettle();

    expect(find.text('복원하지 못했어요. 약 목록은 그대로예요'), findsOneWidget);
    expect(memory.values.single.name, '혈압약');
    expect(memory.values.single.takenRecords, ['2026-01-02_08:00']);
    expect(find.textContaining('복원했어요'), findsNothing);
  });

  // T-261116-043 — 아이폰 기본 백업 = 로그인 없는 iCloud(한줄일기 방식, 대종님 11/16).
  group('아이폰 iCloud 백업', () {
    Uint8List backupOf(List<Medicine> medicines) => MedicineBackup.encode(
      medicines,
      now: DateTime(2026, 11, 16, 19, 5),
      appVersion: '1.2.1+17',
    );

    testWidgets('아이폰은 iCloud 백업과 빈 목록을 파일 두 줄 위에 보여 준다', (tester) async {
      final icloud = _FakeICloud();
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
      expect(find.text('iCloud에서 복원'), findsNothing);
      expect(find.text('어느 백업으로 복원할까요?'), findsNothing);
      expect(find.text('아직 백업이 없어요'), findsOneWidget);
      expect(icloud.listCount, greaterThanOrEqualTo(1));
      expect(find.text(_icloudNotice), findsOneWidget);
      expect(find.text(_iosFileNotice), findsOneWidget);
      expect(find.text(_androidFileNotice), findsNothing);

      final order = ['iCloud에 백업', '아직 백업이 없어요', '파일로 백업', '파일에서 복원'];
      for (final label in order) {
        await tester.ensureVisible(find.text(label));
      }
      final tops = [
        for (final label in order) tester.getTopLeft(find.text(label)).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: order[i]);
      }
      expect(tops.first, greaterThan(tester.getTopLeft(find.text('휴지통')).dy));
    });

    testWidgets('iCloud 백업은 약 목록 전체를 올리고 알려 준다', (tester) async {
      await box.add(pill('혈압약', takenRecords: ['2026-01-02_08:00']));
      await box.add(pill('버린약', hour: 21, deletedAt: DateTime(2026, 11, 1, 9)));
      final icloud = _FakeICloud();
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapRow(tester, 'iCloud에 백업');

      expect(icloud.uploadCount, 1);
      final decoded = MedicineBackup.decode(icloud.uploaded!);
      expect(decoded.medicines.map((m) => m.name).toList(), ['혈압약', '버린약']);
      expect(decoded.medicines.first.takenRecords, ['2026-01-02_08:00']);
      expect(find.text('iCloud에 백업했어요'), findsOneWidget);
    });

    testWidgets('약이 없으면 iCloud 에 올리지 않는다', (tester) async {
      final icloud = _FakeICloud();
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapRow(tester, 'iCloud에 백업');

      expect(find.text('백업할 약이 없어요'), findsOneWidget);
      expect(icloud.uploadCount, 0);
    });

    testWidgets('iCloud 를 못 쓰면 켜는 방법을 알려 주고 올리지 않는다', (tester) async {
      await box.add(pill('혈압약'));
      final icloud = _FakeICloud(available: false);
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapRow(tester, 'iCloud에 백업');

      expect(find.text(_icloudUnavailable), findsOneWidget);
      expect(icloud.uploadCount, 0);
    });

    testWidgets('iCloud 에 올리다 실패하면 실패 안내를 보여 준다', (tester) async {
      await box.add(pill('혈압약'));
      final icloud = _FakeICloud(
        uploadError: PlatformException(code: 'failed'),
      );
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapRow(tester, 'iCloud에 백업');

      expect(
        find.text('iCloud에 백업하지 못했어요. 저장 공간과 iCloud Drive를 확인해 주세요'),
        findsOneWidget,
      );
      expect(find.text('iCloud에 백업했어요'), findsNothing);
    });

    testWidgets('iCloud 목록은 최신이 위에 오고 날짜와 크기를 보여 준다', (tester) async {
      const newer = 'yakmukja-backup-20261116-1905.json';
      const older = 'yakmukja-backup-20261115-0900.json';
      final icloud = _FakeICloud(
        files: [
          _file(older, size: 1536),
          _file(newer, size: 2 * 1024 * 1024),
        ],
      );
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      expect(find.text('2026-11-16 19:05'), findsOneWidget);
      expect(find.text('2026-11-15 09:00'), findsOneWidget);
      expect(find.text('2MB'), findsOneWidget);
      expect(find.text('1.5KB'), findsOneWidget);
      expect(find.text('아직 백업이 없어요'), findsNothing);
      expect(
        tester.getTopLeft(find.text('2026-11-16 19:05')).dy,
        lessThan(tester.getTopLeft(find.text('2026-11-15 09:00')).dy),
      );
    });

    testWidgets('줄의 복원은 그 파일로 확인 창을 거쳐 약 목록을 바꾼다', (tester) async {
      await box.add(pill('혈압약', hour: 9));
      const newer = 'yakmukja-backup-20261116-1905.json';
      const older = 'yakmukja-backup-20261115-0900.json';
      final icloud = _FakeICloud(
        files: [_file(newer), _file(older)],
        payloads: {
          newer: backupOf([pill('비타민', hour: 7)]),
          older: backupOf([pill('옛날약')]),
        },
      );
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapFileAction(tester, older, '복원');

      expect(find.text('어느 백업으로 복원할까요?'), findsNothing);
      expect(icloud.downloaded, older);
      expect(find.text('백업에서 복원할까요?'), findsOneWidget);
      expect(find.text('백업 파일의 약 1개로 바꿔요. 지금 등록된 약 1개는 지워져요.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '복원'));
      await tester.pumpAndSettle();

      expect(box.values.map((m) => m.name).toList(), ['옛날약']);
      expect(find.text('약 1개를 복원했어요'), findsOneWidget);
      expect(icloud.deleteCount, 0);
    });

    testWidgets('iCloud 백업이 끝나면 목록을 다시 불러 온다', (tester) async {
      await box.add(pill('혈압약'));
      final icloud = _FakeICloud(showUploadedFile: true);
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);
      expect(find.text('아직 백업이 없어요'), findsOneWidget);
      final before = icloud.listCount;

      await tapRow(tester, 'iCloud에 백업');

      expect(icloud.uploadCount, 1);
      expect(icloud.listCount, greaterThan(before));
      expect(find.text('2026-11-17 18:00'), findsOneWidget);
      expect(find.text('2KB'), findsOneWidget);
      expect(find.text('아직 백업이 없어요'), findsNothing);
      expect(find.text('iCloud에 백업했어요'), findsOneWidget);
    });

    testWidgets('iCloud 에 백업이 없으면 빈 목록 문구를 보여 준다', (tester) async {
      final icloud = _FakeICloud();
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      expect(find.text('아직 백업이 없어요'), findsOneWidget);
      expect(find.text('iCloud에 약먹자 백업이 없어요'), findsNothing);
      expect(find.text('어느 백업으로 복원할까요?'), findsNothing);
      expect(icloud.listCount, greaterThanOrEqualTo(1));
    });

    testWidgets('iCloud 를 못 쓰면 줄의 복원은 받지 않고 켜는 방법을 알려 준다', (tester) async {
      final icloud = _FakeICloud(available: false, files: [_file(_sample)]);
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      expect(icloud.listCount, greaterThanOrEqualTo(1));
      await tapFileAction(tester, _sample, '복원');

      expect(find.text(_icloudUnavailable), findsOneWidget);
      expect(icloud.downloaded, isNull);
      expect(find.text('백업에서 복원할까요?'), findsNothing);
    });

    testWidgets('복원 확인을 취소하면 약 목록을 바꾸지 않는다', (tester) async {
      await box.add(pill('혈압약'));
      final icloud = _FakeICloud(
        files: [_file(_sample)],
        payloads: {
          _sample: backupOf([pill('비타민')]),
        },
      );
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapFileAction(tester, _sample, '복원');
      expect(find.text('백업에서 복원할까요?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(find.text('백업에서 복원할까요?'), findsNothing);
      expect(box.values.single.name, '혈압약');
      expect(find.text('약 1개를 복원했어요'), findsNothing);
    });

    testWidgets('iCloud 의 백업이 약먹자 것이 아니면 이유를 보여 주고 그대로 둔다', (tester) async {
      await box.add(pill('혈압약'));
      final icloud = _FakeICloud(
        files: [_file(_sample)],
        payloads: {_sample: Uint8List.fromList('{"format":"nope"}'.codeUnits)},
      );
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapFileAction(tester, _sample, '복원');

      expect(find.text('약먹자 백업 파일이 아니에요'), findsOneWidget);
      expect(find.text('백업에서 복원할까요?'), findsNothing);
      expect(box.values.single.name, '혈압약');
    });

    testWidgets('목록을 못 받으면 실패 안내와 다시 시도를 보여 준다', (tester) async {
      final icloud = _FakeICloud(listError: PlatformException(code: 'failed'));
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('아직 백업이 없어요'), findsNothing);
      expect(
        find.text('iCloud에서 백업을 가져오지 못했어요. 인터넷 연결과 iCloud Drive를 확인해 주세요'),
        findsNothing,
      );

      icloud.listError = null;
      icloud.files = [_file(_sample, size: 2048)];
      await tester.ensureVisible(find.text('다시 시도'));
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('2026-11-16 19:05'), findsOneWidget);
      expect(find.text('2KB'), findsOneWidget);
      expect(find.text('목록을 불러오지 못했어요'), findsNothing);
      expect(icloud.listCount, greaterThanOrEqualTo(2));
    });

    testWidgets('목록이 15초 안에 안 오면 실패 안내를 보여 준다', (tester) async {
      final icloud = _FakeICloud(hangList: true);
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      expect(find.text('불러오는 중'), findsOneWidget);
      expect(icloud.listCount, greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 14));
      expect(find.text('불러오는 중'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('목록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('불러오는 중'), findsNothing);
    });

    testWidgets('줄의 지우기는 확인 뒤에 그 파일을 지우고 목록을 다시 불러 온다', (tester) async {
      const newer = 'yakmukja-backup-20261116-1905.json';
      const older = 'yakmukja-backup-20261115-0900.json';
      final icloud = _FakeICloud(
        files: [_file(newer, size: 2048), _file(older, size: 1024)],
      );
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);
      final listsBeforeDelete = icloud.listCount;

      await tapFileAction(tester, newer, '지우기');

      expect(find.text('이 백업을 지울까요? 지우면 되돌릴 수 없어요.'), findsOneWidget);
      expect(icloud.deleteCount, 0);
      await tester.tap(find.widgetWithText(FilledButton, '지우기'));
      await tester.pumpAndSettle();

      expect(icloud.deletedNames, [newer]);
      expect(icloud.listCount, greaterThan(listsBeforeDelete));
      expect(find.text('2026-11-16 19:05'), findsNothing);
      expect(find.text('2026-11-15 09:00'), findsOneWidget);
      expect(find.text('1KB'), findsOneWidget);
    });

    testWidgets('지우기 확인을 취소하면 파일을 지우지 않는다', (tester) async {
      const newer = 'yakmukja-backup-20261116-1905.json';
      const older = 'yakmukja-backup-20261115-0900.json';
      final icloud = _FakeICloud(files: [_file(newer), _file(older)]);
      await pumpSettings(tester, icloud: icloud, platform: TargetPlatform.iOS);

      await tapFileAction(tester, newer, '지우기');
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect(icloud.deleteCount, 0);
      expect(icloud.deletedNames, isEmpty);
      expect(find.text('2026-11-16 19:05'), findsOneWidget);
      expect(find.text('2026-11-15 09:00'), findsOneWidget);
      expect(find.text('이 백업을 지울까요? 지우면 되돌릴 수 없어요.'), findsNothing);
    });

    testWidgets('영어 로캘에서는 빈 목록 문구가 영어다', (tester) async {
      await pumpSettings(
        tester,
        icloud: _FakeICloud(),
        platform: TargetPlatform.iOS,
        locale: const Locale('en'),
      );

      expect(find.text('Back up to iCloud'), findsOneWidget);
      expect(find.text('No backups yet.'), findsOneWidget);
      expect(find.text('아직 백업이 없어요'), findsNothing);
    });

    testWidgets('영어 로캘에서는 줄의 복원·지우기와 확인 창이 영어다', (tester) async {
      final icloud = _FakeICloud(files: [_file(_sample, size: 2048)]);
      await pumpSettings(
        tester,
        icloud: icloud,
        platform: TargetPlatform.iOS,
        locale: const Locale('en'),
      );

      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('2KB'), findsOneWidget);
      await tapFileAction(tester, _sample, 'Delete');
      expect(
        find.text("Delete this backup? This can't be undone."),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(icloud.deleteCount, 0);
    });
  });
}

const _sample = 'yakmukja-backup-20261116-1905.json';

const _icloudNotice =
    '로그인 없이 이 기기의 iCloud에 약 목록과 복용 기록을 저장해요. '
    '같은 Apple 계정의 새 아이폰·아이패드에서 복원할 수 있어요. 최근 백업 5개를 보관해요.';

const _iosFileNotice =
    '안드로이드 폰으로 옮길 때는 파일로 백업해 새 폰에서 복원하세요. '
    '백업 파일에는 약 이름과 복용 기록이 들어 있어요. 믿을 수 있는 곳에 보관해 주세요.';

const _androidFileNotice =
    '폰을 바꾸거나 아이폰으로 옮길 때도 이 파일로 복원하면 돼요. '
    '백업 파일에는 약 이름과 복용 기록이 들어 있어요. 믿을 수 있는 곳에 보관해 주세요.';

const _icloudUnavailable =
    'iCloud를 쓸 수 없어요. 설정에서 Apple 계정에 로그인하고 iCloud Drive를 켜 주세요';

ICloudBackupFile _file(String name, {int size = 1}) =>
    ICloudBackupFile(name: name, modified: DateTime(2026), size: size);

class _FakeICloud extends ICloudMedicineBackup {
  _FakeICloud({
    this.available = true,
    List<ICloudBackupFile> files = const [],
    this.payloads = const {},
    this.listError,
    this.uploadError,
    this.hangList = false,
    this.showUploadedFile = false,
  }) : files = [...files];

  final bool available;
  List<ICloudBackupFile> files;
  final Map<String, Uint8List> payloads;
  Object? listError;
  final Object? uploadError;
  bool hangList;
  bool showUploadedFile;
  int uploadCount = 0;
  int listCount = 0;
  int deleteCount = 0;
  final deletedNames = <String>[];
  Uint8List? uploaded;
  String? downloaded;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> upload(Uint8List bytes, {DateTime? now}) async {
    if (uploadError != null) throw uploadError!;
    uploadCount += 1;
    uploaded = Uint8List.fromList(bytes);
    if (showUploadedFile) {
      files = [_file('yakmukja-backup-20261117-1800.json', size: 2048)];
    }
  }

  @override
  Future<List<ICloudBackupFile>> list() async {
    listCount += 1;
    if (hangList) await Completer<void>().future;
    if (listError != null) throw listError!;
    return List<ICloudBackupFile>.from(files);
  }

  @override
  Future<Uint8List> download(String name) async {
    downloaded = name;
    return payloads[name]!;
  }

  @override
  Future<void> delete(String name) async {
    deleteCount += 1;
    deletedNames.add(name);
    files.removeWhere((file) => file.name == name);
  }
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
