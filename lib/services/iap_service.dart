import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광고 제거 구매 시도 결과. UI 가 적절한 안내를 띄울 수 있도록 동기적으로 판별되는
/// 상태만 구분한다. 실제 구매 성공은 비동기 스트림([_onPurchaseUpdated])으로 도착해
/// [IapService.adsRemoved] 를 반응형으로 갱신하므로 여기서는 [started] 까지만 본다.
enum IapResult {
  /// 결제 시트를 띄웠다(성공 여부는 스트림으로 도착).
  started,

  /// 스토어 자체에 연결 불가(시뮬레이터/오프라인 등).
  unavailable,

  /// 스토어에 상품이 아직 없음(등록·승인 전 또는 productId 불일치).
  productNotFound,

  /// 이미 광고가 제거된 상태.
  alreadyOwned,
}

/// 광고 제거 비소모성(non-consumable) 인앱결제.
///
/// 구매(또는 복원) 시 [adsRemoved] 를 true 로 바꾸고 SharedPreferences 에 persist 한다.
/// 배너 위젯이 [adsRemoved] 를 구독하므로 구매 즉시 광고가 사라진다.
/// 비소모성 상품이 스토어에 등록돼 있어야 실제 구매가 동작한다(상품 등록은 별도 게이트,
/// 코드는 등록 전에도 안전). productId 는 플랫폼별로 다르다 — Android(Play)는 앱 단위
/// 스코프라 `remove_ads`, iOS(ASC)는 productId 가 개발자계정 전역 유일이라 reverse-DNS
/// 네임스페이스 `com.daejongkang.yakmukja.remove_ads` 를 쓴다 (메모요가 `remove_ads` 선점).
class IapService {
  static final String removeAdsProductId =
      Platform.isIOS ? 'com.daejongkang.yakmukja.remove_ads' : 'remove_ads';
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

  /// 구매 복원. 기기 변경/재설치 후 사용자가 직접 호출할 수 있는 public 래퍼.
  /// 스토어 연결에 성공해 복원을 요청했으면 true(실제 복원 결과는 스트림으로 도착),
  /// 스토어 자체에 연결 못 하면 false.
  static Future<bool> restorePurchases() async {
    if (!await _iap.isAvailable()) return false;
    await _iap.restorePurchases();
    return true;
  }

  /// 광고 제거 구매 시작. 동기적으로 판별 가능한 결과를 [IapResult] 로 반환해
  /// UI 가 실패 사유를 안내할 수 있게 한다.
  static Future<IapResult> buyRemoveAds() async {
    if (adsRemoved.value) return IapResult.alreadyOwned;
    if (!await _iap.isAvailable()) return IapResult.unavailable;

    final response = await _iap.queryProductDetails({removeAdsProductId});
    if (response.productDetails.isEmpty) {
      debugPrint('[IapService] product not found: $removeAdsProductId');
      return IapResult.productNotFound;
    }
    final param = PurchaseParam(productDetails: response.productDetails.first);
    await _iap.buyNonConsumable(purchaseParam: param);
    return IapResult.started;
  }

  /// 구매 결과에 대응하는 사용자 안내 문구. [IapResult.started] 는 네이티브 결제
  /// 시트가 뜨므로 별도 안내가 불필요해 null 을 반환한다.
  static String? purchaseMessage(IapResult result) {
    switch (result) {
      case IapResult.started:
        return null;
      case IapResult.unavailable:
        return '스토어에 연결할 수 없어요. 잠시 후 다시 시도해주세요.';
      case IapResult.productNotFound:
        return '아직 상품을 준비 중이에요. 잠시 후 다시 시도해주세요.';
      case IapResult.alreadyOwned:
        return '이미 광고가 제거되어 있어요.';
    }
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
