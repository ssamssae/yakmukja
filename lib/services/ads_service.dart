import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import 'iap_service.dart';

/// AdMob 초기화 + 광고 단위 ID 관리.
///
/// 정책: iOS·Android 양 플랫폼 운영 배너를 활성화한다. (2026-06-15 Android AdMob
/// 앱/배너 유닛 발급 + Play 프로덕션 제출과 함께 Android 광고 연결.)
class AdsService {
  static bool _initialized = false;
  static Future<void>? _initializing;

  static bool get isSupportedPlatform => Platform.isIOS || Platform.isAndroid;

  static Future<void> init() {
    if (!isSupportedPlatform) return Future<void>.value();
    if (_initialized) return Future<void>.value();
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;

    _initializing = _init();
    return _initializing!;
  }

  static Future<void> _init() async {
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('[AdsService] init failed: $e');
    } finally {
      _initializing = null;
    }
  }

  /// 배너 광고 단위 ID. 출시판만 실제 ID 이고, 디버그·프로필 빌드는 구글 공식 시험 ID 다.
  /// iOS 는 출시판이라도 앱스토어에서 받은 설치만 실제 ID 다. TestFlight·개발 서명 설치는 시험 ID 다.
  /// 개발·실기기 시험이나 TestFlight 에서 실광고가 노출·클릭되면 무효 트래픽으로 게시자 계정이
  /// 정지된다(2026-11-04 29일 정지, T-261104-014 B안).
  static Future<String> bannerAdUnitId() async => bannerAdUnitIdFor(
    releaseMode: kReleaseMode,
    platform: Platform.isIOS
        ? TargetPlatform.iOS
        : Platform.isAndroid
        ? TargetPlatform.android
        : defaultTargetPlatform,
    installerStore: await installerStore,
  );

  static Future<String?>? _installerStore;

  /// 설치 출처. iOS 는 앱스토어 설치면 `com.apple`, TestFlight·개발 서명 설치면 `com.apple.testflight` 다
  /// (package_info_plus 가 영수증 경로 `sandboxReceipt` 로 가른다). 읽지 못하면 null 이다.
  @visibleForTesting
  static Future<String?> get installerStore =>
      _installerStore ??= _readInstallerStore();

  static Future<String?> _readInstallerStore() async {
    try {
      return (await PackageInfo.fromPlatform()).installerStore;
    } catch (_) {
      return null;
    }
  }

  /// [bannerAdUnitId] 의 순수 함수판 — 빌드 모드·플랫폼·설치 출처 분기를 단위 시험으로 고정한다.
  ///
  /// iOS 는 [installerStore] 가 정확히 `com.apple`(앱스토어 설치)일 때만 실제 배너다.
  /// TestFlight·개발 서명·시뮬레이터·모름(null)은 시험 배너다. 안드로이드는 내부 테스트와
  /// 정식 출시가 같은 앱 묶음이라 설치 출처로 가를 수 없어 출시판이면 실제 배너다.
  /// 그 밖의 플랫폼은 종전처럼 시험 배너다.
  @visibleForTesting
  static String bannerAdUnitIdFor({
    required bool releaseMode,
    required TargetPlatform platform,
    required String? installerStore,
  }) {
    final ios = platform == TargetPlatform.iOS;
    final android = platform == TargetPlatform.android;
    final storeInstall = android || (ios && installerStore == 'com.apple');
    if (!releaseMode || !storeInstall) {
      return android ? _testAndroidBannerUnitId : _testIosBannerUnitId;
    }
    return ios ? _realIosBannerUnitId : _realAndroidBannerUnitId;
  }

  static const _testIosBannerUnitId = 'ca-app-pub-3940256099942544/2934735716';
  static const _testAndroidBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  // iOS 운영 ID — 2026-05-02 AdMob 콘솔 발급.
  static const _realIosBannerUnitId = 'ca-app-pub-7025432711849670/6770114012';

  // Android 운영 ID — 2026-06-15 AdMob 콘솔 발급 (앱 ca-app-pub-...~1874025882).
  static const _realAndroidBannerUnitId =
      'ca-app-pub-7025432711849670/2883855221';
}

class AdaptiveBanner extends StatefulWidget {
  const AdaptiveBanner({super.key});

  @override
  State<AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<AdaptiveBanner> {
  BannerAd? _bannerAd;
  bool _loaded = false;
  AdSize? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kScreenshotMode) return; // 스토어 스크린샷 캡처 모드 → 광고 로드 안 함
    if (!AdsService.isSupportedPlatform) return;
    if (IapService.adsRemoved.value) return; // 광고 제거 구매됨 → 로드 안 함
    if (_bannerAd == null) {
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    await AdsService.init();
    if (!mounted) return;

    final mq = MediaQuery.of(context);
    final width = mq.size.width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    // 광고 단위는 설치 출처를 읽은 뒤에 정해진다(T-261104-014).
    final adUnitId = await AdsService.bannerAdUnitId();
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdaptiveBanner] failed: ${error.message}');
          ad.dispose();
        },
      ),
    );

    setState(() => _size = size);
    await ad.load();
    if (!mounted) {
      ad.dispose();
      return;
    }
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdsService.isSupportedPlatform) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: IapService.adsRemoved,
      builder: (context, removed, _) {
        final size = _size;
        if (removed || !_loaded || _bannerAd == null || size == null) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          child: SizedBox(
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        );
      },
    );
  }
}
