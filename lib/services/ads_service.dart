import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob 초기화 + 광고 단위 ID 관리.
///
/// 정책: 약먹자는 iOS-only 출시 상태를 유지한다. AdMob 도 iOS 운영 배너만
/// 활성화하고, Android 는 Play 출시 보류 상태라 SDK init/banner load 를 하지 않는다.
class AdsService {
  static bool _initialized = false;
  static Future<void>? _initializing;

  static bool get isSupportedPlatform => Platform.isIOS;

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
    if (kDebugMode) return _testIosBannerUnitId;
    if (Platform.isIOS) return _realIosBannerUnitId;
    return _testIosBannerUnitId;
  }

  static const _testIosBannerUnitId = 'ca-app-pub-3940256099942544/2934735716';

  // iOS 운영 ID — 2026-05-02 AdMob 콘솔 발급.
  static const _realIosBannerUnitId = 'ca-app-pub-7025432711849670/6770114012';
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
    final size = _size;
    if (!_loaded || _bannerAd == null || size == null) {
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
  }
}
