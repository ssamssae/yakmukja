import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/app_review_service.dart';

/// 꾸준히 쓴 사람에게만, 드물게 스토어 평가를 부탁한다. (T-261110-040)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.britannio.in_app_review');
  final calls = <String>[];
  var available = true;
  var requestFails = false;

  setUp(() {
    calls.clear();
    available = true;
    requestFails = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isAvailable') return available;
          if (call.method == 'requestReview' && requestFails) {
            throw PlatformException(code: 'fail');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final now = DateTime(2026, 11, 10, 9, 0);

  bool ask({
    int activeDays = 5,
    DateTime? firstUse,
    bool neverUsed = false,
    DateTime? lastAsked,
    int askedCount = 0,
  }) => AppReviewService.shouldAskForReview(
    now: now,
    activeDays: activeDays,
    firstUse: neverUsed ? null : (firstUse ?? DateTime(2026, 10, 1)),
    lastAsked: lastAsked,
    askedCount: askedCount,
  );

  group('부탁해도 되는가', () {
    test('꾸준히 썼고 부탁한 적이 없으면 부탁한다', () {
      expect(ask(), isTrue);
    });

    test('「먹었어요」를 표시한 날이 5일이 안 되면 부탁하지 않는다', () {
      expect(ask(activeDays: 4), isFalse);
      expect(ask(activeDays: 5), isTrue);
    });

    test('첫 약을 등록한 지 7일이 안 됐으면 부탁하지 않는다', () {
      expect(ask(firstUse: DateTime(2026, 11, 4, 9, 0)), isFalse);
      expect(ask(firstUse: DateTime(2026, 11, 3, 9, 0)), isTrue);
    });

    test('등록한 약이 없으면 부탁하지 않는다', () {
      expect(ask(neverUsed: true), isFalse);
    });

    test('마지막으로 부탁한 지 90일이 안 됐으면 부탁하지 않는다', () {
      expect(
        ask(lastAsked: DateTime(2026, 8, 13, 9, 0), askedCount: 1),
        isFalse,
      );
      expect(
        ask(lastAsked: DateTime(2026, 8, 12, 9, 0), askedCount: 1),
        isTrue,
      );
    });

    test('세 번 부탁했으면 더 부탁하지 않는다', () {
      expect(ask(lastAsked: DateTime(2025, 1, 1), askedCount: 2), isTrue);
      expect(ask(lastAsked: DateTime(2025, 1, 1), askedCount: 3), isFalse);
    });
  });

  Medicine medicine({
    List<String> taken = const [],
    DateTime? createdAt,
    DateTime? deletedAt,
  }) => Medicine(
    name: '혈압약',
    dosage: '1알',
    times: [DoseTime(hour: 8, minute: 0)],
    memo: '',
    createdAt: createdAt ?? DateTime(2026, 10, 1),
    takenRecords: [...taken],
    deletedAt: deletedAt,
  );

  group('쓴 날 세기', () {
    test('「먹었어요」를 표시한 서로 다른 날을 센다', () {
      final days = AppReviewService.activeDoseDays([
        medicine(taken: ['2026-11-08_08:00', '2026-11-09_08:00']),
        medicine(taken: ['2026-11-09_21:00', '2026-11-10_08:00']),
      ]);

      expect(days, 3);
    });

    test('기록이 없으면 0일이다', () {
      expect(AppReviewService.activeDoseDays([medicine()]), 0);
    });
  });

  group('부탁하기', () {
    // 서로 다른 5일에 표시한 약.
    List<Medicine> steady() => [
      medicine(
        taken: [
          '2026-11-06_08:00',
          '2026-11-07_08:00',
          '2026-11-08_08:00',
          '2026-11-09_08:00',
          '2026-11-10_08:00',
        ],
      ),
    ];

    test('조건이 맞으면 평가 창을 한 번 부탁하고 시각과 횟수를 적는다', () async {
      final asked = await AppReviewService.maybeAskForReview(
        steady(),
        now: now,
      );

      expect(asked, isTrue);
      expect(calls, ['isAvailable', 'requestReview']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('review_prompt_count'), 1);
      expect(prefs.getInt('review_prompt_last_ms'), now.millisecondsSinceEpoch);
    });

    test('방금 부탁했으면 다시 부탁하지 않는다', () async {
      await AppReviewService.maybeAskForReview(steady(), now: now);
      calls.clear();

      final again = await AppReviewService.maybeAskForReview(
        steady(),
        now: now.add(const Duration(days: 1)),
      );

      expect(again, isFalse);
      expect(calls, isEmpty);
    });

    test('조건이 안 맞으면 스토어에 묻지도 않는다', () async {
      final asked = await AppReviewService.maybeAskForReview([
        medicine(taken: ['2026-11-10_08:00']),
      ], now: now);

      expect(asked, isFalse);
      expect(calls, isEmpty);
    });

    test('기기가 평가 창을 띄울 수 없으면 부탁하지 않고 횟수도 세지 않는다', () async {
      available = false;

      final asked = await AppReviewService.maybeAskForReview(
        steady(),
        now: now,
      );

      expect(asked, isFalse);
      expect(calls, ['isAvailable']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('review_prompt_count'), isNull);
    });

    test('평가 창 부르기가 실패해도 예외를 던지지 않는다', () async {
      requestFails = true;

      final asked = await AppReviewService.maybeAskForReview(
        steady(),
        now: now,
      );

      expect(asked, isFalse);
    });

    test('부탁 시각이 미래면 지금부터 90일을 세고 그 시각까지 잠그지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_last_ms': DateTime(2027, 11, 10).millisecondsSinceEpoch,
        'review_prompt_count': 1,
      });

      final askedNow = await AppReviewService.maybeAskForReview(
        steady(),
        now: now,
      );

      expect(askedNow, isFalse);
      expect(calls, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('review_prompt_last_ms'), now.millisecondsSinceEpoch);
      expect(prefs.getInt('review_prompt_count'), 1);

      final askedSoon = await AppReviewService.maybeAskForReview(
        steady(),
        now: now.add(const Duration(days: 89)),
      );
      expect(askedSoon, isFalse);

      calls.clear();
      final askedLater = await AppReviewService.maybeAskForReview(
        steady(),
        now: now.add(const Duration(days: 90)),
      );
      expect(askedLater, isTrue);
      expect(calls, ['isAvailable', 'requestReview']);
    });

    test('저장소 읽기가 실패해도 예외를 던지지 않는다', () async {
      // 저장된 값이 깨져 있으면 읽는 쪽에서 예외가 난다. 화면을 막지 않고 부탁하지 않는다.
      SharedPreferences.setMockInitialValues({
        'review_prompt_last_ms': 'broken',
      });

      final asked = await AppReviewService.maybeAskForReview(
        steady(),
        now: now,
      );

      expect(asked, isFalse);
      expect(calls, isEmpty);
    });

    test('휴지통 약의 기록과 등록일도 쓴 기간으로 친다', () async {
      // 약을 정리해 지웠어도 꾸준히 쓴 사람이다.
      final asked = await AppReviewService.maybeAskForReview([
        medicine(
          taken: [
            '2026-11-06_08:00',
            '2026-11-07_08:00',
            '2026-11-08_08:00',
            '2026-11-09_08:00',
          ],
          deletedAt: DateTime(2026, 11, 9, 22, 0),
        ),
        medicine(
          taken: ['2026-11-10_08:00'],
          createdAt: DateTime(2026, 11, 10, 7, 0),
        ),
      ], now: now);

      expect(asked, isTrue);
    });
  });
}
