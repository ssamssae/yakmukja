import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

  static String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _testAndroidBannerUnitId : _testIosBannerUnitId;
    }
    if (Platform.isIOS) return _realIosBannerUnitId;
    if (Platform.isAndroid) return _realAndroidBannerUnitId;
    return _testIosBannerUnitId;
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

    final ad = BannerAd(
      adUnitId: AdsService.bannerAdUnitId,
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
