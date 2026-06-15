import 'package:in_app_review/in_app_review.dart';

/// 앱 평가 — 네이티브 인앱 리뷰 프롬프트를 띄운다. (T-260614-12)
class AppReviewService {
  static final InAppReview _inAppReview = InAppReview.instance;

  /// 평가 프롬프트 요청. 사용 불가하면 false.
  static Future<bool> requestReview() async {
    try {
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
