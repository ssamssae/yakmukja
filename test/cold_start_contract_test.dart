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
