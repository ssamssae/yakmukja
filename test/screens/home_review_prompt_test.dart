import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/screens/home_screen.dart';
import 'package:yakmukja/screens/main_shell.dart';
import 'package:yakmukja/services/notification_service.dart';
import 'package:yakmukja/theme/app_theme.dart';
import 'package:yakmukja/widgets/renewal_check.dart';

/// 오늘 약을 다 먹은 순간, 꾸준히 쓴 사람에게 평가를 부탁한다. (T-261110-040)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.britannio.in_app_review');
  final calls = <String>[];
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
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isAvailable') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDownAll(() async {
    await box.close();
  });

  // 복용 체크는 실제 오늘 날짜에 남는다. 시각만 정한다.
  DateTime todayAt(int hour, int minute) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  /// 어제부터 거꾸로 [days]일 동안 아침 8:00 에 표시한 기록.
  List<String> pastRecords(int days) {
    final now = DateTime.now();
    return [
      for (var back = 1; back <= days; back++)
        () {
          final d = DateTime(now.year, now.month, now.day - back);
          final date =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return '${date}_08:00';
        }(),
    ];
  }

  Future<Medicine> add(
    String name, {
    int hour = 8,
    int minute = 0,
    int pastDays = 5,
  }) async {
    final medicine = Medicine(
      name: name,
      dosage: '1알',
      times: [DoseTime(hour: hour, minute: minute)],
      memo: '',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      takenRecords: pastRecords(pastDays),
    );
    await box.add(medicine);
    return medicine;
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: () => todayAt(8, 5)),
      ),
    );
    await tester.pump();
  }

  Future<void> flushAsk(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// 평가 부탁까지의 기다림과 그 뒤의 저장·스토어 호출을 흘려보낸다.
  Future<void> waitForAsk(WidgetTester tester) async {
    await tester.pump(reviewAskDelay + const Duration(milliseconds: 100));
    await flushAsk(tester);
  }

  /// resumed → inactive → hidden → paused. 한 단계만 건너뛰면 수명주기 단언이 난다.
  void leaveApp(WidgetTester tester) {
    final binding = tester.binding;
    final state = binding.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    if (binding.lifecycleState == AppLifecycleState.inactive) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }
  }

  void returnToApp(WidgetTester tester) {
    final binding = tester.binding;
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    if (binding.lifecycleState == AppLifecycleState.inactive ||
        binding.lifecycleState == AppLifecycleState.detached) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }

  testWidgets('마지막 약을 「먹었어요」로 누르면 잠시 뒤 평가 창을 부탁한다', (tester) async {
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    // 다 먹은 화면이 먼저 보이고, 곧바로 부탁하지는 않는다.
    expect(find.byKey(const Key('home-all-done')), findsOneWidget);
    expect(calls, isEmpty);

    await waitForAsk(tester);

    expect(calls, ['isAvailable', 'requestReview']);
  });

  testWidgets('약이 남아 있으면 부탁하지 않는다', (tester) async {
    await add('혈압약');
    await add('수면 보조제', hour: 22);
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('「먹었어요」를 표시한 날이 5일이 안 되면 부탁하지 않는다', (tester) async {
    // 지난 이틀 + 오늘 = 3일.
    await add('혈압약', pastDays: 2);
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('약을 지워서 다 먹은 상태가 된 것이면 부탁하지 않는다', (tester) async {
    final done = await add('혈압약');
    final left = await add('수면 보조제', hour: 22);
    done.toggleTaken(done.times.first);
    await pumpHome(tester);

    // 남은 약을 휴지통으로 보낸다.
    left.deletedAt = DateTime.now();
    await tester.runAsync(left.save);
    await tester.pump();
    expect(find.byKey(const Key('home-all-done')), findsOneWidget);
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('다 먹었다가 바로 되돌리면 부탁하지 않는다', (tester) async {
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    // 「오늘 나머지」 목록의 체크를 다시 눌러 되돌린다.
    await tester.tap(find.byType(RenewalCheck));
    await tester.pump();
    expect(find.byKey(const Key('home-all-done')), findsNothing);
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('이미 다 먹은 상태로 화면을 열면 부탁하지 않는다', (tester) async {
    final done = await add('혈압약');
    done.toggleTaken(done.times.first);
    await pumpHome(tester);

    expect(find.byKey(const Key('home-all-done')), findsOneWidget);
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('다 먹은 뒤 앱이 뒤로 가 있으면 부탁하지 않는다', (tester) async {
    addTearDown(() => returnToApp(tester));
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    leaveApp(tester);
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('다 먹은 뒤 다른 화면으로 넘어가 있으면 부탁하지 않는다', (tester) async {
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    // 목록의 약 이름을 눌러 수정 화면을 연다.
    await tester.tap(find.text('혈압약'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('뒤로 갔다가 다시 앞으로 오면 그 순간의 부탁은 하지 않는다', (tester) async {
    addTearDown(() => returnToApp(tester));
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    leaveApp(tester);
    returnToApp(tester);
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('설정 탭을 보고 있는 동안은 부탁하지 않는다', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.1.1',
      buildNumber: '14',
      buildSignature: '',
    );
    await add('혈압약');
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MainShell()),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    await tester.tap(find.text('설정'));
    await tester.pump();
    expect(find.text('앱 평가하기'), findsOneWidget);

    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('설정 탭에 갔다가 1.2초 안에 약목록으로 돌아오면 부탁한다', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '1.1.1',
      buildNumber: '14',
      buildSignature: '',
    );
    await add('혈압약');
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const MainShell()),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    await tester.tap(find.text('설정'));
    await tester.pump();
    await tester.tap(find.text('약목록'));
    await tester.pump();
    await waitForAsk(tester);

    expect(calls, ['isAvailable', 'requestReview']);
  });

  testWidgets('대화창이 위에 있으면 부탁하지 않는다', (tester) async {
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    final homeContext = tester.element(find.byType(HomeScreen));
    unawaited(
      showDialog<void>(
        context: homeContext,
        builder: (context) => const AlertDialog(content: Text('다른 일')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('화면을 닫은 뒤 타이머가 돌아도 부탁하지 않는다', (tester) async {
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await waitForAsk(tester);

    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('오래된 기록 정리와 휴지통 만료 삭제는 다 먹은 순간으로 치지 않는다', (tester) async {
    final today = await add('혈압약');
    today.toggleTaken(today.times.first);
    final old = DateTime.now().subtract(const Duration(days: 40));
    today.takenRecords = [...today.takenRecords, Medicine.recordKey(old, 8, 0)];
    await today.save();
    final expired = await add('버린 약', hour: 21);
    expired.deletedAt = DateTime.now().subtract(const Duration(days: 31));
    await expired.save();
    await pumpHome(tester);
    expect(find.byKey(const Key('home-all-done')), findsOneWidget);

    await tester.runAsync(() async {
      final cutoff = DateTime.now().subtract(Medicine.trashRetention);
      for (final medicine in box.values.toList()) {
        medicine.pruneOldRecords();
        if (medicine.deletedAt != null &&
            medicine.deletedAt!.isBefore(cutoff)) {
          await medicine.delete();
        }
      }
    });
    await tester.pump();
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('한 번에 여러 체크가 들어와도 부탁은 한 번만 한다', (tester) async {
    final morning = await add('혈압약');
    final night = await add('수면 보조제', hour: 22);
    await pumpHome(tester);

    morning.toggleTaken(morning.times.first);
    night.toggleTaken(night.times.first);
    await tester.pump();
    await waitForAsk(tester);

    expect(calls, ['isAvailable', 'requestReview']);
  });

  testWidgets('오늘만 먹는 약이 다음 날로 넘어가면 부탁하지 않는다', (tester) async {
    final realNow = DateTime.now();
    var now = DateTime(realNow.year, realNow.month, realNow.day, 8, 5);
    final medicine = Medicine(
      name: '혈압약',
      dosage: '1알',
      times: [DoseTime(hour: 8, minute: 0)],
      memo: '',
      createdAt: realNow.subtract(const Duration(days: 30)),
      takenRecords: pastRecords(5),
      weekdays: [realNow.weekday],
    );
    await box.add(medicine);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(clock: () => now),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    now = now.add(const Duration(days: 1));
    await waitForAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('모두 먹었어요 되돌리기 안내가 있는 동안은 부탁하지 않는다', (tester) async {
    await add('혈압약');
    await add('비타민');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-all-button')));
    await tester.pump();
    expect(find.text('되돌리기'), findsOneWidget);

    await tester.pump(reviewAskDelay + const Duration(milliseconds: 100));
    await tester.pump();
    expect(calls, isEmpty);

    await tester.tap(find.text('되돌리기'));
    await tester.pump();
    await tester.pump(takeAllNoticeDuration);
    await flushAsk(tester);

    expect(calls, isEmpty);
  });

  testWidgets('되돌리기 안내가 스스로 내려가고 여전히 다 먹었으면 그때 부탁한다', (tester) async {
    await add('혈압약');
    await add('비타민');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-all-button')));
    await tester.pump();
    await tester.pump(reviewAskDelay + const Duration(milliseconds: 100));
    expect(calls, isEmpty);

    // 안내 시간 6초 + 내려가는 움직임. 분 타이머가 있어 pumpAndSettle 은 쓰지 않는다.
    await tester.pump(takeAllNoticeDuration);
    await tester.pump(const Duration(milliseconds: 500));
    await flushAsk(tester);

    expect(calls, ['isAvailable', 'requestReview']);
  });

  testWidgets('스토어에 묻는 동안 되돌리면 부탁하지 않고 횟수도 세지 않는다', (tester) async {
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isAvailable') {
            await gate.future;
            return true;
          }
          return null;
        });
    await add('혈압약');
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-take-button')));
    await tester.pump();
    await tester.pump(reviewAskDelay + const Duration(milliseconds: 50));
    await flushAsk(tester);
    expect(calls, ['isAvailable']);

    await tester.tap(find.byType(RenewalCheck));
    await tester.pump();
    gate.complete();
    await flushAsk(tester);

    expect(calls, ['isAvailable']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('review_prompt_count'), isNull);
  });
}
