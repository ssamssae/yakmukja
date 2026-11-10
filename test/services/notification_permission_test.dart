import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/models/medicine.dart';
import 'package:yakmukja/services/notification_service.dart';

import '../support/fake_notification_center.dart';

/// 알림 권한이 꺼져 있는지 알고, 켜지면 알림을 다시 건다. (T-261110-026)
List<Medicine> meds() => [
  Medicine(
    name: '혈압약',
    dosage: '1알',
    times: [DoseTime(hour: 8, minute: 0)],
    memo: '',
    createdAt: DateTime(2026, 11, 1),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationCenter center;

  // 알림 서비스는 앱 전체에서 하나다. 시험마다 처음 상태에서 시작한다.
  setUp(NotificationService.resetForTest);

  tearDown(() {
    center.uninstall();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('$platform', () {
      setUp(() {
        center = FakeNotificationCenter()..install(platform);
      });

      test('기기에서 알림이 꺼져 있으면 꺼짐으로 안다', () async {
        center
          ..enabled = false
          ..grantOnRequest = false;

        await NotificationService.initAndSync(meds);

        expect(NotificationService.enabled.value, isFalse);
      });

      test('기기에서 알림이 켜져 있으면 켜짐으로 안다', () async {
        await NotificationService.initAndSync(meds);

        expect(NotificationService.enabled.value, isTrue);
      });

      test('꺼져 있던 알림이 켜진 것을 알게 되면 약 목록대로 알림을 다시 건다', () async {
        center
          ..enabled = false
          ..grantOnRequest = false;
        await NotificationService.initAndSync(meds);
        center.pending.clear();

        // 사용자가 기기 설정에서 알림을 켜고 앱으로 돌아왔다.
        center.enabled = true;
        await NotificationService.refreshPermission();

        expect(NotificationService.enabled.value, isTrue);
        expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
      });

      test('「알림 켜기」에서 허용하면 켜짐이 되고 알림이 걸린다', () async {
        center
          ..enabled = false
          ..grantOnRequest = false;
        await NotificationService.initAndSync(meds);
        center.pending.clear();

        center.grantOnRequest = true;
        final result = await NotificationService.requestEnable();

        expect(result, NotificationEnableResult.granted);
        expect(NotificationService.enabled.value, isTrue);
        expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
      });
    });
  }

  test('iOS: 다시 물어도 꺼져 있으면 앱 설정 화면을 연다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    center
      ..enabled = false
      ..grantOnRequest = false;
    await NotificationService.initAndSync(meds);

    final result = await NotificationService.requestEnable();

    expect(result, NotificationEnableResult.openedSettings);
    expect(center.launchedUrls, ['app-settings:']);
    expect(NotificationService.enabled.value, isFalse);
  });

  test('안드로이드: 다시 물어도 꺼져 있으면 손으로 켜야 한다고 알려 준다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.android);
    center
      ..enabled = false
      ..grantOnRequest = false;
    await NotificationService.initAndSync(meds);

    final result = await NotificationService.requestEnable();

    expect(result, NotificationEnableResult.needsManual);
    expect(center.launchedUrls, isEmpty);
    expect(NotificationService.enabled.value, isFalse);
  });
}
