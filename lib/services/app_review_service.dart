import 'package:in_app_review/in_app_review.dart';

/// 앱 평가 — App Store / Play Store 리뷰 페이지를 연다. (T-260614-12)
///
/// 수동 '앱 평가하기' 버튼은 자동 프롬프트(requestReview)가 아니라 스토어
/// 리뷰 페이지로 직접 보낸다. requestReview 의 네이티브 시트는 dev/TestFlight
/// 빌드에서 '보내기'가 무동작(Apple 정책)이고, 수동 버튼엔 부적합하다.
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
}
