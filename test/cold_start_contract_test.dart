import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'main shows the first frame before notification and ads startup work',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(source, isNot(contains('await NotificationService.init();')));
      expect(source, isNot(contains('await AdsService.init();')));

      final runAppIndex = source.indexOf('runApp(');
      final deferredIndex = source.indexOf('_startDeferredColdStartWork();');
      expect(runAppIndex, isNonNegative);
      expect(deferredIndex, isNonNegative);
      expect(runAppIndex, lessThan(deferredIndex));
    },
  );

  test('startup re-syncs device alarms with the medicine list', () {
    final source = File('lib/main.dart').readAsStringSync();

    // 앱을 켤 때 알림 준비만 하고 「다시 맞추기」를 빼면, 빠졌거나 기기에서 사라진
    // 예약이 스스로 복구되지 않는다. (T-261110-023)
    expect(source, contains('NotificationService.initAndSync('));
    expect(source, isNot(contains('NotificationService.init,')));
  });

  test('startup restores ad removal without waiting for the alarm step', () {
    final source = File('lib/main.dart').readAsStringSync();

    // 알림 준비는 권한 창이 닫힐 때까지 기다릴 수 있다. 광고 제거 구매 복원이 그 뒤로
    // 밀리면 구매한 사람에게 배너가 잠깐 보인다. 반대로 알림 맞추기도 스토어 연결을
    // 기다리지 않는다 — 둘은 서로 기다리지 않고 같이 간다. (T-261110-023 검토)
    final iapIndex = source.indexOf("'IapService.init'");
    final alarmIndex = source.indexOf("'NotificationService.initAndSync'");
    expect(iapIndex, isNonNegative);
    expect(alarmIndex, isNonNegative);
    expect(iapIndex, lessThan(alarmIndex));
    expect(
      RegExp(
        r"await _runDeferredStartupStep\(\s*'IapService\.init'",
      ).hasMatch(source),
      isFalse,
    );
  });

  test('banner ad loading initializes ads lazily after the first frame', () {
    final source = File('lib/services/ads_service.dart').readAsStringSync();

    final lazyInitIndex = source.indexOf('await AdsService.init();');
    final bannerAdIndex = source.indexOf('BannerAd(');
    expect(lazyInitIndex, isNonNegative);
    expect(bannerAdIndex, isNonNegative);
    expect(lazyInitIndex, lessThan(bannerAdIndex));
  });

  test('ads init coalesces concurrent cold-start and banner requests', () {
    final source = File('lib/services/ads_service.dart').readAsStringSync();

    expect(source, contains('static Future<void>? _initializing;'));
    expect(source, contains('final inFlight = _initializing;'));
    expect(source, contains('if (inFlight != null) return inFlight;'));
  });
}
