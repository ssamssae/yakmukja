import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medicine.dart';

/// 앱 평가 — App Store / Play Store 리뷰 페이지를 연다. (T-260614-12)
///
/// 수동 '앱 평가하기' 버튼은 자동 프롬프트(requestReview)가 아니라 스토어
/// 리뷰 페이지로 직접 보낸다. requestReview 의 네이티브 시트는 dev/TestFlight
/// 빌드에서 '보내기'가 무동작(Apple 정책)이고, 수동 버튼엔 부적합하다.
///
/// 평가 부탁(자동) — 꾸준히 쓴 사람이 오늘 약을 다 먹은 순간에만, 드물게
/// 스토어의 평가 창을 부탁한다. (T-261110-040)
class AppReviewService {
  static final InAppReview _inAppReview = InAppReview.instance;

  /// iOS App Store 숫자 id (com.ssamssae.yakmukja). Android 는 패키지로 자동.
  static const String _appStoreId = '6762100639';

  /// 스토어 리뷰 페이지 열기. 실패 시 false.
  static Future<bool> openReview() async {
    try {
      await _inAppReview.openStoreListing(appStoreId: _appStoreId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 「먹었어요」를 표시한 날이 이만큼은 돼야 부탁한다.
  static const int minActiveDays = 5;

  /// 첫 약을 등록한 뒤 이만큼(일)은 지나야 부탁한다.
  static const int minDaysSinceFirstUse = 7;

  /// 한 번 부탁하면 이만큼(일)은 다시 부탁하지 않는다.
  static const int minDaysBetweenAsks = 90;

  /// 이 횟수만큼 부탁했으면 더 부탁하지 않는다.
  static const int maxAsks = 3;

  static const String _lastAskedKey = 'review_prompt_last_ms';
  static const String _askedCountKey = 'review_prompt_count';

  /// 평가를 부탁해도 되는가.
  static bool shouldAskForReview({
    required DateTime now,
    required int activeDays,
    required DateTime? firstUse,
    required DateTime? lastAsked,
    required int askedCount,
  }) {
    if (activeDays < minActiveDays) return false;
    if (firstUse == null) return false;
    if (now.difference(firstUse) < const Duration(days: minDaysSinceFirstUse)) {
      return false;
    }
    if (askedCount >= maxAsks) return false;
    if (lastAsked != null &&
        now.difference(lastAsked) < const Duration(days: minDaysBetweenAsks)) {
      return false;
    }
    return true;
  }

  /// 「먹었어요」를 표시한 서로 다른 날 수. 기록은 최근 30일만 남는다.
  /// 휴지통 약의 기록도 센다 — 약을 지웠어도 그날 앱을 쓴 것은 같다.
  static int activeDoseDays(Iterable<Medicine> medicines) {
    final days = <String>{};
    for (final medicine in medicines) {
      for (final record in medicine.takenRecords) {
        // "yyyy-MM-dd_HH:mm" 의 날짜 부분.
        if (record.length >= 10) days.add(record.substring(0, 10));
      }
    }
    return days.length;
  }

  /// 오늘 약을 다 먹은 순간에 부른다. 조건이 맞으면 스토어의 평가 창을 부탁하고
  /// true 를 돌려준다. 창이 실제로 떴는지는 스토어가 알려 주지 않으므로, 부탁한 것을
  /// 기준으로 시각과 횟수를 적는다. 실패해도 예외를 던지지 않는다.
  ///
  /// [stillWanted] 가 false 를 돌려주면(그 사이 되돌림·다른 화면) 창을 부탁하지
  /// 않고 횟수도 늘리지 않는다. 저장이 느린 사이를 위해 적은 직후에도 한 번 더 본다.
  static Future<bool> maybeAskForReview(
    Iterable<Medicine> medicines, {
    DateTime? now,
    bool Function()? stillWanted,
  }) async {
    try {
      final at = now ?? DateTime.now();
      final all = medicines.toList();
      DateTime? firstUse;
      for (final medicine in all) {
        if (firstUse == null || medicine.createdAt.isBefore(firstUse)) {
          firstUse = medicine.createdAt;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (stillWanted != null && !stillWanted()) return false;
      final storedLastMs = prefs.getInt(_lastAskedKey);
      var lastAsked = storedLastMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(storedLastMs);
      // 시계를 앞으로 당겼다 되돌리면 부탁 시각이 미래로 남는다. 그 시각까지
      // 잠그지 않고, 지금부터 90일을 세도록 지금으로 고친다.
      if (lastAsked != null && lastAsked.isAfter(at)) {
        lastAsked = at;
        await prefs.setInt(_lastAskedKey, at.millisecondsSinceEpoch);
        if (stillWanted != null && !stillWanted()) return false;
      }
      final baselineLastMs = prefs.getInt(_lastAskedKey);
      final askedCount = prefs.getInt(_askedCountKey) ?? 0;
      final ok = shouldAskForReview(
        now: at,
        activeDays: activeDoseDays(all),
        firstUse: firstUse,
        lastAsked: lastAsked,
        askedCount: askedCount,
      );
      if (!ok) return false;
      if (stillWanted != null && !stillWanted()) return false;
      if (!await _inAppReview.isAvailable()) return false;
      if (stillWanted != null && !stillWanted()) return false;
      // 부르기 전에 적는다 — 부르다 실패해도 곧바로 또 부탁하지 않게 한다.
      await prefs.setInt(_lastAskedKey, at.millisecondsSinceEpoch);
      await prefs.setInt(_askedCountKey, askedCount + 1);
      if (stillWanted != null && !stillWanted()) {
        await _restoreAskRecord(
          prefs,
          lastMs: baselineLastMs,
          askedCount: askedCount,
        );
        return false;
      }
      await _inAppReview.requestReview();
      return true;
    } catch (e, st) {
      debugPrint('[AppReviewService.maybeAskForReview] failed: $e\n$st');
      return false;
    }
  }

  static Future<void> _restoreAskRecord(
    SharedPreferences prefs, {
    required int? lastMs,
    required int askedCount,
  }) async {
    if (lastMs == null) {
      await prefs.remove(_lastAskedKey);
    } else {
      await prefs.setInt(_lastAskedKey, lastMs);
    }
    if (askedCount == 0) {
      await prefs.remove(_askedCountKey);
    } else {
      await prefs.setInt(_askedCountKey, askedCount);
    }
  }
}
