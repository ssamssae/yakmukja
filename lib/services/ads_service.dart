import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'iap_service.dart';

/// AdMob 초기화 + 광고 단위 ID 관리.
///
/// 정책: iOS·Android 양 플랫폼 운영 배너를 활성화한다. (2026-06-15 Android AdMob
/// 앱/배너 유닛 발급 + Play 프로덕션 제출과 함께 Android 광고 연결.)
class AdsService {
  static bool _initialized = false;
  static Future<void>? _initializing;

  /// 처음 본 시각. epoch 밀리초. 한 번 저장하면 덮어쓰지 않는다.
  static const firstSeenPrefsKey = 'ads_first_seen_ms';

  /// 설치 후 이 시간보다 짧으면 실제 광고를 요청하지 않는다.
  static const installGrace = Duration(hours: 72);

  static bool get isSupportedPlatform =>
      debugSupportedPlatform ?? (Platform.isIOS || Platform.isAndroid);

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
        releaseMode: debugReleaseMode ?? kReleaseMode,
        platform: debugPlatform ?? _hostPlatform,
        installerStore: await installerStore,
      );

  /// 디버그 대체가 없을 때의 플랫폼. [bannerAdUnitId] 와 유예 판정이 같은 식을 쓴다.
  static TargetPlatform get _hostPlatform {
    if (Platform.isIOS) return TargetPlatform.iOS;
    if (Platform.isAndroid) return TargetPlatform.android;
    return defaultTargetPlatform;
  }

  static Future<String?>? _installerStore;

  /// 설치 출처. iOS 는 앱스토어 설치면 `com.apple`, TestFlight·개발 서명 설치면 `com.apple.testflight` 다
  /// (package_info_plus 가 영수증 경로 `sandboxReceipt` 로 가른다). 읽지 못하면 null 이다.
  @visibleForTesting
  static Future<String?> get installerStore => _installerStore ??= _readInstallerStore();

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

  /// `now` 가 `firstSeen` 보다 과거이거나, 둘의 차이가 [installGrace] 보다 짧으면 참이다.
  /// 72시간 0분은 유예가 아니다. 시계를 뒤로 돌린 기기에는 광고를 내지 않는다.
  @visibleForTesting
  static bool inInstallGrace({
    required DateTime now,
    required DateTime firstSeen,
  }) {
    final elapsed = now.difference(firstSeen);
    if (elapsed.isNegative) return true;
    return elapsed < installGrace;
  }

  /// 저장값이 있으면 그 시각이다. 없으면 설치 시각, 설치 시각도 없거나 읽기에 실패하면 [now] 다.
  /// 저장은 값이 없을 때만 한다.
  @visibleForTesting
  static Future<DateTime> resolveFirstSeen({
    required DateTime now,
    required int? storedMs,
    required Future<void> Function(int milliseconds) saveMs,
    required Future<DateTime?> Function() readInstallTime,
  }) async {
    if (storedMs != null) {
      return DateTime.fromMillisecondsSinceEpoch(storedMs);
    }
    DateTime chosen;
    try {
      chosen = await readInstallTime() ?? now;
    } catch (_) {
      chosen = now;
    }
    await saveMs(chosen.millisecondsSinceEpoch);
    return chosen;
  }

  /// 실제 광고 단위를 쓰는 조건일 때만 설치 유예를 본다.
  /// 시험 광고 조건(디버그·프로필·TestFlight·그 밖 플랫폼)은 처음 본 시각을 읽지도 저장하지도 않는다.
  static Future<bool> shouldSuppressRealAdsForInstallGrace() {
    final future = _shouldSuppressRealAdsForInstallGrace();
    debugLastRealAdGrace = future;
    return future;
  }

  static Future<bool> _shouldSuppressRealAdsForInstallGrace() async {
    final adUnitId = await bannerAdUnitId();
    if (adUnitId != _realIosBannerUnitId &&
        adUnitId != _realAndroidBannerUnitId) {
      return false;
    }
    final now = debugNow?.call() ?? DateTime.now();
    final firstSeen = await _readStoredFirstSeen(now);
    return inInstallGrace(now: now, firstSeen: firstSeen);
  }

  static Future<DateTime> _readStoredFirstSeen(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return resolveFirstSeen(
      now: now,
      storedMs: prefs.getInt(firstSeenPrefsKey),
      saveMs: (milliseconds) async {
        await prefs.setInt(firstSeenPrefsKey, milliseconds);
      },
      readInstallTime: debugReadInstallTime ?? _readInstallTime,
    );
  }

  static Future<DateTime?> _readInstallTime() async {
    final info = await PackageInfo.fromPlatform();
    return info.installTime;
  }

  @visibleForTesting
  static DateTime Function()? debugNow;

  @visibleForTesting
  static bool? debugReleaseMode;

  @visibleForTesting
  static TargetPlatform? debugPlatform;

  @visibleForTesting
  static bool? debugSupportedPlatform;

  /// null 이면 [PackageInfo.installTime] 을 읽는다. 예외를 던지면 현재 시각을 쓴다.
  @visibleForTesting
  static Future<DateTime?> Function()? debugReadInstallTime;

  /// null 이면 [BannerAd.load] 를 부른다. 시험은 여기서 로드를 대신한다.
  @visibleForTesting
  static Future<void> Function(BannerAd ad)? debugLoadBanner;

  @visibleForTesting
  static int bannerAdsCreatedForTest = 0;

  /// 배너가 유예 판정을 시작했으면 그 Future. 시험이 판정이 끝난 뒤에 광고 객체를 센다.
  @visibleForTesting
  static Future<bool>? debugLastRealAdGrace;

  @visibleForTesting
  static void debugClearInstallerStoreCache() {
    _installerStore = null;
  }

  @visibleForTesting
  static void debugReset() {
    debugNow = null;
    debugReleaseMode = null;
    debugPlatform = null;
    debugSupportedPlatform = null;
    debugReadInstallTime = null;
    debugLoadBanner = null;
    bannerAdsCreatedForTest = 0;
    debugLastRealAdGrace = null;
    _installerStore = null;
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
  bool _loadInFlight = false;

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
    // 유예 판정이 비동기라, 판정 중에 didChangeDependencies 가 다시 와도
    // 배너를 두 번 만들지 않는다.
    if (_loadInFlight || _bannerAd != null) return;
    _loadInFlight = true;
    try {
      await _loadAdOnce();
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _loadAdOnce() async {
    // 광고 제거 구매는 didChangeDependencies 에서 이미 먼저 본다.
    // 유예 중에는 광고 SDK 를 초기화하지 않고 배너 객체도 만들지 않는다.
    if (IapService.adsRemoved.value) return;
    final suppress = await AdsService.shouldSuppressRealAdsForInstallGrace();
    if (!mounted || IapService.adsRemoved.value || suppress) return;

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
    AdsService.bannerAdsCreatedForTest++;
    final customLoad = AdsService.debugLoadBanner;
    if (customLoad != null) {
      await customLoad(ad);
    } else {
      await ad.load();
    }
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
