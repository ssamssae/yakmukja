// T-261112-016: 설치 후 72시간 동안 실제 배너 광고를 요청하지 않는다.
// 71시간 59분은 유예, 72시간 0분은 유예 아님, 시계를 뒤로 돌리면 유예다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yakmukja/services/ads_service.dart';
import 'package:yakmukja/services/iap_service.dart';

const _iosReal = 'ca-app-pub-7025432711849670/6770114012';
const _androidReal = 'ca-app-pub-7025432711849670/2883855221';
const _adsChannel = MethodChannel('plugins.flutter.io/google_mobile_ads');

void _setPackage({String? installerStore, DateTime? installTime}) {
  PackageInfo.setMockInitialValues(
    appName: '약먹자',
    packageName: 'com.ssamssae.yakmukja',
    version: '1.2.0',
    buildNumber: '15',
    buildSignature: '',
    installerStore: installerStore,
    installTime: installTime,
  );
  AdsService.debugClearInstallerStoreCache();
}

void main() {
  final first = DateTime.utc(2026, 11, 1);

  setUp(() {
    AdsService.debugReset();
    IapService.adsRemoved.value = false;
    SharedPreferences.setMockInitialValues({});
    _setPackage(installerStore: 'com.apple');
  });

  tearDown(() {
    AdsService.debugReset();
    IapService.adsRemoved.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_adsChannel, null);
  });

  group('inInstallGrace', () {
    test('71시간 59분은 유예다', () {
      final now = first.add(const Duration(hours: 71, minutes: 59));
      expect(AdsService.inInstallGrace(now: now, firstSeen: first), isTrue);
    });

    test('72시간 0분은 유예가 아니다', () {
      final now = first.add(const Duration(hours: 72));
      expect(AdsService.inInstallGrace(now: now, firstSeen: first), isFalse);
    });

    test('현재 시각이 처음 본 시각보다 과거면 유예다', () {
      expect(
        AdsService.inInstallGrace(
          now: first.subtract(const Duration(minutes: 1)),
          firstSeen: first,
        ),
        isTrue,
      );
      // 72시간을 넘긴 과거도 유예다. 차이를 절댓값으로 재면 이 경우가 깨진다.
      expect(
        AdsService.inInstallGrace(
          now: first.subtract(const Duration(hours: 73)),
          firstSeen: first,
        ),
        isTrue,
      );
    });
  });

  group('resolveFirstSeen', () {
    test('저장값이 있으면 그 값을 쓰고 덮어쓰지 않는다', () async {
      final stored = DateTime.utc(2024, 5, 6, 7, 8, 9);
      var saves = 0;
      var reads = 0;
      final seen = await AdsService.resolveFirstSeen(
        now: DateTime.utc(2026, 11, 12),
        storedMs: stored.millisecondsSinceEpoch,
        saveMs: (_) async => saves++,
        readInstallTime: () async {
          reads++;
          return DateTime.utc(2020);
        },
      );
      expect(seen.millisecondsSinceEpoch, stored.millisecondsSinceEpoch);
      expect(saves, 0);
      expect(reads, 0);
    });

    test('저장값이 없으면 설치 시각을 골라 저장한다', () async {
      final install = DateTime.utc(2020, 1, 2, 3, 4, 5);
      int? saved;
      final seen = await AdsService.resolveFirstSeen(
        now: DateTime.utc(2026, 11, 12),
        storedMs: null,
        saveMs: (milliseconds) async => saved = milliseconds,
        readInstallTime: () async => install,
      );
      expect(seen.millisecondsSinceEpoch, install.millisecondsSinceEpoch);
      expect(saved, install.millisecondsSinceEpoch);
    });

    test('설치 시각이 없으면 현재 시각을 저장한다', () async {
      final now = DateTime.utc(2026, 11, 12, 1, 2, 3);
      int? saved;
      final seen = await AdsService.resolveFirstSeen(
        now: now,
        storedMs: null,
        saveMs: (milliseconds) async => saved = milliseconds,
        readInstallTime: () async => null,
      );
      expect(seen.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
      expect(saved, now.millisecondsSinceEpoch);
    });

    test('설치 시각 읽기에 실패하면 현재 시각을 저장한다', () async {
      final now = DateTime.utc(2026, 11, 12, 4, 5, 6);
      int? saved;
      final seen = await AdsService.resolveFirstSeen(
        now: now,
        storedMs: null,
        saveMs: (milliseconds) async => saved = milliseconds,
        readInstallTime: () async => throw StateError('install time'),
      );
      expect(seen.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
      expect(saved, now.millisecondsSinceEpoch);
    });
  });

  group('shouldSuppressRealAdsForInstallGrace', () {
    test('저장값이 있으면 설치 시각이 달라도 그 값을 유지하고 오래된 사용자는 유예가 아니다', () async {
      final stored = DateTime.utc(2024, 1, 2);
      final now = DateTime.utc(2026, 11, 12);
      SharedPreferences.setMockInitialValues({
        AdsService.firstSeenPrefsKey: stored.millisecondsSinceEpoch,
      });
      _setPackage(installerStore: 'com.apple', installTime: now);
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.iOS;
      AdsService.debugNow = () => now;

      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(AdsService.firstSeenPrefsKey),
        stored.millisecondsSinceEpoch,
      );
    });

    test('저장값이 없으면 package_info_plus 설치 시각을 저장하고 다시 쓰지 않는다', () async {
      final install = DateTime.utc(2020, 3, 4);
      final now = DateTime.utc(2026, 11, 12);
      _setPackage(installerStore: 'com.apple', installTime: install);
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.iOS;
      AdsService.debugNow = () => now;

      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(AdsService.firstSeenPrefsKey),
        install.millisecondsSinceEpoch,
      );

      _setPackage(installerStore: 'com.apple', installTime: now);
      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);
      expect(
        prefs.getInt(AdsService.firstSeenPrefsKey),
        install.millisecondsSinceEpoch,
      );
    });

    test('설치 시각이 없으면 현재 시각을 저장하고 유예다', () async {
      final now = DateTime.utc(2026, 11, 12, 8);
      _setPackage(installerStore: 'com.apple');
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.iOS;
      AdsService.debugNow = () => now;

      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(AdsService.firstSeenPrefsKey),
        now.millisecondsSinceEpoch,
      );
    });

    test('설치 시각 읽기에 실패하면 현재 시각을 저장하고 유예다', () async {
      final now = DateTime.utc(2026, 11, 12, 9);
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.iOS;
      AdsService.debugNow = () => now;
      AdsService.debugReadInstallTime = () async => throw StateError('boom');

      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(AdsService.firstSeenPrefsKey),
        now.millisecondsSinceEpoch,
      );
    });

    test('안드로이드 출시판도 설치 후 71시간 59분이면 유예다', () async {
      final now = DateTime.utc(2026, 11, 12, 10);
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.android;
      AdsService.debugNow = () => now;
      _setPackage(
        installerStore: 'com.android.vending',
        installTime: now.subtract(const Duration(hours: 71, minutes: 59)),
      );

      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isTrue);
    });

    test('디버그·TestFlight·그 밖 플랫폼은 유예를 보지 않고 처음 본 시각도 쓰지 않는다', () async {
      final now = DateTime.utc(2026, 11, 12);
      AdsService.debugNow = () => now;
      AdsService.debugPlatform = TargetPlatform.iOS;

      AdsService.debugReleaseMode = false;
      _setPackage(installerStore: 'com.apple', installTime: now);
      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);

      AdsService.debugReleaseMode = true;
      _setPackage(installerStore: 'com.apple.testflight', installTime: now);
      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);

      AdsService.debugPlatform = TargetPlatform.macOS;
      _setPackage(installerStore: 'com.apple', installTime: now);
      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AdsService.firstSeenPrefsKey), isNull);
    });

    test('72시간이 지나면 유예가 아니고 bannerAdUnitIdFor 반환은 지금과 같다', () async {
      final now = first.add(const Duration(hours: 72));
      SharedPreferences.setMockInitialValues({
        AdsService.firstSeenPrefsKey: first.millisecondsSinceEpoch,
      });
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.iOS;
      AdsService.debugNow = () => now;
      _setPackage(installerStore: 'com.apple', installTime: DateTime.utc(2020));

      expect(await AdsService.shouldSuppressRealAdsForInstallGrace(), isFalse);
      expect(
        AdsService.bannerAdUnitIdFor(
          releaseMode: true,
          platform: TargetPlatform.iOS,
          installerStore: 'com.apple',
        ),
        _iosReal,
      );
      expect(
        AdsService.bannerAdUnitIdFor(
          releaseMode: true,
          platform: TargetPlatform.android,
          installerStore: null,
        ),
        _androidReal,
      );
    });
  });

  group('AdaptiveBanner 유예', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_adsChannel, (call) async {
            calls.add(call.method);
            return null;
          });
    });

    Future<void> pumpBanner(WidgetTester tester) {
      return tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [AdaptiveBanner(), Expanded(child: SizedBox())],
            ),
          ),
        ),
      );
    }

    void armRealIosRelease(DateTime now) {
      AdsService.debugNow = () => now;
      AdsService.debugReleaseMode = true;
      AdsService.debugPlatform = TargetPlatform.iOS;
      AdsService.debugSupportedPlatform = true;
      _setPackage(installerStore: 'com.apple');
    }

    testWidgets('유예 중에는 광고 객체를 만들지 않고 자리도 차지하지 않는다', (tester) async {
      final now = DateTime.utc(2026, 11, 12, 12);
      SharedPreferences.setMockInitialValues({
        AdsService.firstSeenPrefsKey: now
            .subtract(const Duration(hours: 71, minutes: 59))
            .millisecondsSinceEpoch,
      });
      armRealIosRelease(now);
      var loadCalled = false;
      AdsService.debugLoadBanner = (_) async => loadCalled = true;

      await pumpBanner(tester);
      final decision = AdsService.debugLastRealAdGrace;
      expect(decision, isNotNull);
      expect(await decision, isTrue);
      await tester.pump();

      expect(AdsService.bannerAdsCreatedForTest, 0);
      expect(loadCalled, isFalse);
      expect(calls, isEmpty);
      expect(find.byType(AdWidget), findsNothing);
      expect(tester.getSize(find.byType(AdaptiveBanner)).height, 0);
    });

    testWidgets('광고 제거 구매가 먼저라 유예 저장도 광고 요청도 하지 않는다', (tester) async {
      final now = DateTime.utc(2026, 11, 12, 12);
      IapService.adsRemoved.value = true;
      armRealIosRelease(now);
      _setPackage(installerStore: 'com.apple', installTime: now);

      await pumpBanner(tester);
      final decision = AdsService.debugLastRealAdGrace;
      if (decision != null) await decision;
      await tester.pump();

      expect(AdsService.bannerAdsCreatedForTest, 0);
      expect(calls, isEmpty);
      expect(tester.getSize(find.byType(AdaptiveBanner)).height, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AdsService.firstSeenPrefsKey), isNull);
    });
  });
}
