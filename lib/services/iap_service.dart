import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광고 제거 비소모성(non-consumable) 인앱결제.
///
/// 구매(또는 복원) 시 [adsRemoved] 를 true 로 바꾸고 SharedPreferences 에 persist 한다.
/// 배너 위젯이 [adsRemoved] 를 구독하므로 구매 즉시 광고가 사라진다.
/// 스토어(Play Console / App Store Connect)에 productId `remove_ads` 비소모성 상품이
/// 등록돼 있어야 실제 구매가 동작한다(상품 등록은 별도 게이트, 코드는 등록 전에도 안전).
class IapService {
  static const String removeAdsProductId = 'remove_ads';
  static const String _prefsKey = 'iap_ads_removed';

  /// 광고 제거 여부. ValueListenableBuilder 로 구독해 구매 즉시 UI 반영.
  static final ValueNotifier<bool> adsRemoved = ValueNotifier<bool>(false);

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;

  /// 앱 시작 시 1회 호출. persist 값 복원 + 구매 스트림 구독 + 기존 구매 복원.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    adsRemoved.value = prefs.getBool(_prefsKey) ?? false;

    final available = await _iap.isAvailable();
    if (!available) return;

    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: (Object e) => debugPrint('[IapService] stream error: $e'),
    );

    // 기기 변경/재설치 시 광고 제거 상태 유지 (비소모성이라 복원 가능).
    await _iap.restorePurchases();
  }

  /// 광고 제거 구매 시작. 이미 제거됐으면 no-op.
  static Future<void> buyRemoveAds() async {
    if (adsRemoved.value) return;
    if (!await _iap.isAvailable()) return;

    final response = await _iap.queryProductDetails({removeAdsProductId});
    if (response.productDetails.isEmpty) {
      debugPrint('[IapService] product not found: $removeAdsProductId');
      return;
    }
    final param = PurchaseParam(productDetails: response.productDetails.first);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  static Future<void> _onPurchaseUpdated(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.productID != removeAdsProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _setRemoved(true);
          break;
        case PurchaseStatus.error:
          debugPrint('[IapService] purchase error: ${purchase.error}');
          break;
        default: // pending / canceled — 별도 처리 없음
          break;
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  static Future<void> _setRemoved(bool value) async {
    adsRemoved.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
