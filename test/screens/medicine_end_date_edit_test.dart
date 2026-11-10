import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 등록·수정 화면에서 끝나는 날을 고르고 지우고 저장한다. (T-261110-042)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<Medicine> box;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MedicineAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(DoseTimeAdapter());
    box = await Hive.openBox<Medicine>(medicineBoxName, bytes: Uint8List(0));
  });

  setUp(() async {
    NotificationService.resetForTest();
    await box.clear();
  });

  tearDownAll(() async {
    await box.close();
  });

  Future<Medicine> addMedicine({DateTime? endDate}) async {
    await box.add(
      Medicine(
        name: '항생제',
        dosage: '1알',
        times: [DoseTime(hour: 8, minute: 0)],
        memo: '',
        createdAt: DateTime(2026, 11, 1),
        endDate: endDate,
      ),
    );
    return box.values.single;
  }

  Future<void> pumpEdit(
    WidgetTester tester, {
    Medicine? medicine,
    DateTime Function()? now,
  }) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MedicineEditScreen(medicine: medicine, now: now),
      ),
    );
    await tester.pumpAndSettle();
  }

  String labelOf(DateTime date) => '${date.year}년 ${date.month}월 ${date.day}일';

  testWidgets('새 약 화면은 끝나는 날이 비어 있다', (tester) async {
    await pumpEdit(tester);

    expect(find.text('끝나는 날'), findsOneWidget);
    expect(find.text('정하지 않음'), findsOneWidget);
    expect(find.text('정하지 않으면 계속 먹는 약이에요.'), findsOneWidget);
    expect(find.byKey(const Key('end-date-clear')), findsNothing);
  });

  testWidgets('날짜를 고르면 그날 0시로 저장한다', (tester) async {
    final medicine = await addMedicine();
    // 오늘이 11월 말이어도 대상은 같은 달이다. 실제 시계에 기대지 않는다.
    final today = DateTime(2026, 11, 10);
    final target = DateTime(2026, 11, 15);
    await pumpEdit(tester, medicine: medicine, now: () => today);

    await tester.ensureVisible(find.byKey(const Key('end-date-field')));
    await tester.tap(find.byKey(const Key('end-date-field')));
    await tester.pumpAndSettle();

    expect(find.text('끝나는 날'), findsWidgets);
    await tester.tap(find.text('${target.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();

    expect(find.text(labelOf(target)), findsOneWidget);
    expect(find.text('이 날까지 먹어요. 다음 날부터는 오늘 목록과 알림에서 빠져요.'), findsOneWidget);

    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.endDate, DateTime(target.year, target.month, target.day));
  });

  testWidgets('지우기를 누르면 끝나는 날이 없어지고 저장하면 계속 먹는 약이 된다', (tester) async {
    final medicine = await addMedicine(endDate: DateTime(2026, 11, 20, 15, 30));
    await pumpEdit(tester, medicine: medicine);

    expect(find.text('2026년 11월 20일'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('end-date-clear')));
    await tester.tap(find.byKey(const Key('end-date-clear')));
    await tester.pumpAndSettle();

    expect(find.text('정하지 않음'), findsOneWidget);
    expect(find.byKey(const Key('end-date-clear')), findsNothing);

    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.endDate, isNull);
  });

  testWidgets('이미 지난 끝나는 날도 보이게 두고 날짜만 저장한다', (tester) async {
    final today = DateTime(2026, 11, 10);
    final past = DateTime(today.year, today.month, today.day - 9, 15, 30);
    final medicine = await addMedicine(endDate: past);
    await pumpEdit(tester, medicine: medicine, now: () => today);

    expect(
      find.text(labelOf(DateTime(past.year, past.month, past.day))),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('end-date-field')));
    await tester.tap(find.byKey(const Key('end-date-field')));
    await tester.pumpAndSettle();
    // 지난 날을 첫날로 열 수 있어야 한다. 고르지 못한 날이면 여기서 예외가 난다.
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.endDate, DateTime(past.year, past.month, past.day));
  });

  testWidgets('끝나는 날을 건드리지 않고 저장하면 비어 있는 그대로다', (tester) async {
    final medicine = await addMedicine();
    await pumpEdit(tester, medicine: medicine);

    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.endDate, isNull);
  });

  testWidgets('월말에는 다음 달로 넘긴 뒤 그달 날짜를 0시로 저장한다', (tester) async {
    final medicine = await addMedicine();
    // 11월 28일의 달력에는 3일이 이번 달의 지난 날로 있다. 다음 달의 3일을 고른다.
    final today = DateTime(2026, 11, 28);
    final target = DateTime(2026, 12, 3);
    await pumpEdit(tester, medicine: medicine, now: () => today);

    await tester.ensureVisible(find.byKey(const Key('end-date-field')));
    await tester.tap(find.byKey(const Key('end-date-field')));
    await tester.pumpAndSettle();

    // 주입한 오늘이 달력의 오늘이어야 한다. 실제 시계면 이 글이 없다.
    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('28, 2026년 11월 28일 토요일, 오늘'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();

    expect(find.text('2026년 12월'), findsOneWidget);
    await tester.tap(find.text('${target.day}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();

    expect(find.text(labelOf(target)), findsOneWidget);

    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(medicine.endDate, target);
  });
}
