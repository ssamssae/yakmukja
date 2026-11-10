import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';

/// 큰 글씨·좁은 화면·긴 요일에서도 홈 큰 카드의 글이 칸 밖으로 넘치지 않는다.
/// (T-261110-037)
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

  DateTime todayAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  /// 오늘 요일을 포함해 [count]개 요일을 고른다(오늘 먹는 약이 되게).
  List<int> weekdaysIncludingToday(int count) {
    final today = DateTime.now().weekday;
    return [for (var i = 0; i < count; i++) (today - 1 + i) % 7 + 1]..sort();
  }

  Future<void> add({
    String dosage = '1알',
    int hour = 8,
    int minute = 0,
    List<int>? weekdays,
  }) => box.add(
    Medicine(
      name: '혈압약',
      dosage: dosage,
      times: [DoseTime(hour: hour, minute: minute)],
      memo: '',
      createdAt: DateTime(2026, 11, 1),
      weekdays: weekdays,
    ),
  );

  Future<void> pumpHome(
    WidgetTester tester,
    DateTime now, {
    required double width,
    double textScale = 1,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: () => now),
      ),
    );
    await tester.pump();
  }

  /// 큰 카드(「먹었어요」 단추가 든 흰 카드)의 가로 범위.
  Rect cardRect(WidgetTester tester) => tester.getRect(
    find
        .ancestor(
          of: find.byKey(const Key('home-take-button')),
          matching: find.byType(Material),
        )
        .first,
  );

  group('윗줄(「다음 약」+남은 시간)', () {
    testWidgets('폭 320·글씨 1.3배에서 「2시간 지남」이 넘치지 않는다', (tester) async {
      await add();
      await pumpHome(tester, todayAt(10, 0), width: 320, textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.text('2시간 지남'), findsOneWidget);
    });

    testWidgets('폭 320·글씨 1.3배에서 긴 「10시간 50분 지남」도 넘치지 않고 카드 안에 있다', (
      tester,
    ) async {
      await add();
      await pumpHome(tester, todayAt(18, 50), width: 320, textScale: 1.3);

      expect(tester.takeException(), isNull);
      final card = cardRect(tester);
      final remain = tester.getRect(find.text('10시간 50분 지남'));
      expect(remain.right, lessThanOrEqualTo(card.right));
      expect(remain.left, greaterThanOrEqualTo(card.left));
    });

    testWidgets('폭 360·글씨 2배에서 「30분 남음」이 넘치지 않는다', (tester) async {
      await add(hour: 21, minute: 30);
      await pumpHome(tester, todayAt(21, 0), width: 360, textScale: 2);

      expect(tester.takeException(), isNull);
      final card = cardRect(tester);
      final remain = tester.getRect(find.text('30분 남음'));
      expect(remain.right, lessThanOrEqualTo(card.right));
    });

    testWidgets('폭 320·글씨 2배에서도 넘치지 않는다', (tester) async {
      await add(hour: 21, minute: 30);
      await pumpHome(tester, todayAt(21, 0), width: 320, textScale: 2);

      expect(tester.takeException(), isNull);
    });

    testWidgets('폭 320·글씨 2배에서 긴 「10시간 50분 지남」은 줄을 바꿔 카드 안에 들어온다', (
      tester,
    ) async {
      await add();
      await pumpHome(tester, todayAt(18, 50), width: 320, textScale: 2);

      expect(tester.takeException(), isNull);
      final card = cardRect(tester);
      final remain = tester.getRect(find.text('10시간 50분 지남'));
      expect(remain.right, lessThanOrEqualTo(card.right));
    });

    testWidgets('보통 화면(폭 390)에서는 종전처럼 한 줄이고 남은 시간이 오른쪽 끝에 붙는다', (tester) async {
      await add(hour: 21, minute: 30);
      await pumpHome(tester, todayAt(21, 0), width: 390);

      expect(tester.takeException(), isNull);
      final chip = tester.getRect(find.text('다음 약'));
      final remain = tester.getRect(find.text('30분 남음'));
      // 같은 줄.
      expect((chip.center.dy - remain.center.dy).abs(), lessThan(2));
      // 카드 안쪽 여백(22) 오른쪽 끝.
      expect(remain.right, closeTo(cardRect(tester).right - 22, 0.5));
    });
  });

  group('꼬리표 줄(복용량+요일)', () {
    testWidgets('폭 375에서 요일 6개와 「2캡슐」이 넘치지 않는다', (tester) async {
      await add(dosage: '2캡슐', weekdays: weekdaysIncludingToday(6));
      await pumpHome(tester, todayAt(8, 5), width: 375);

      expect(tester.takeException(), isNull);
      expect(find.text('2캡슐'), findsOneWidget);
    });

    testWidgets('폭 320에서 요일 6개와 「10방울」이 넘치지 않는다', (tester) async {
      await add(dosage: '10방울', weekdays: weekdaysIncludingToday(6));
      await pumpHome(tester, todayAt(8, 5), width: 320);

      expect(tester.takeException(), isNull);
    });

    testWidgets('폭 320·글씨 2배에서 넘치지 않는다', (tester) async {
      await add(dosage: '2캡슐', weekdays: weekdaysIncludingToday(6));
      await pumpHome(tester, todayAt(8, 5), width: 320, textScale: 2);

      expect(tester.takeException(), isNull);
    });

    testWidgets('보통 화면(폭 390)에서 「1알」「매일」은 종전처럼 한 줄에 나란히 있다', (tester) async {
      await add();
      await pumpHome(tester, todayAt(8, 5), width: 390);

      expect(tester.takeException(), isNull);
      final dosage = tester.getRect(find.text('1알'));
      final days = tester.getRect(find.text('매일'));
      expect((dosage.center.dy - days.center.dy).abs(), lessThan(1));
      expect(days.left, greaterThan(dosage.right));
    });
  });
}
