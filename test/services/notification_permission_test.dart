import 'dart:async';

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

  test('「알림 켜기」를 연달아 불러도 권한은 한 번만 묻는다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.android);
    center
      ..enabled = false
      ..grantOnRequest = false;
    await NotificationService.initAndSync(meds);
    int asked() => center.methods
        .where((m) => m == 'requestNotificationsPermission')
        .length;
    final askedBefore = asked();

    // 첫 요청이 아직 답을 못 받은 사이에 한 번 더 누른다.
    final gate = Completer<void>();
    center.hold = gate.future;
    final first = NotificationService.requestEnable();
    final second = NotificationService.requestEnable();
    center.hold = null;
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(asked() - askedBefore, 1);
    expect(results, [
      NotificationEnableResult.needsManual,
      NotificationEnableResult.needsManual,
    ]);
  });

  test('알림 준비를 한 적이 없으면 권한을 읽지 않는다 — 스토어 화면 캡처 때 꺼짐 안내가 뜨지 않게', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    center.enabled = false;

    await NotificationService.refreshPermission();

    expect(center.methods, isEmpty);
    expect(NotificationService.enabled.value, isNull);
  });

  test('알림 준비가 실패했으면 권한 상태를 말하지 않는다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    center
      ..timezoneFails = true
      ..enabled = false;
    await NotificationService.initAndSync(meds);

    await NotificationService.refreshPermission();

    // 준비가 안 됐는데 「꺼짐→켜짐」을 말하면, 알림이 걸리지 않았는데도 화면이 괜찮다고 한다.
    expect(center.methods, isNot(contains('checkPermissions')));
    expect(NotificationService.enabled.value, isNull);
  });

  test('iOS: 설정 화면을 열지 못하면 손으로 켜야 한다고 알려 준다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    center
      ..enabled = false
      ..grantOnRequest = false
      ..launchFails = true;
    await NotificationService.initAndSync(meds);

    final result = await NotificationService.requestEnable();

    expect(result, NotificationEnableResult.needsManual);
  });

  test('처음엔 권한을 못 읽었다가 켜져 있음을 알게 되면 알림을 다시 건다', () async {
    center = FakeNotificationCenter()..install(TargetPlatform.iOS);
    center.permissionReadFails = true;
    await NotificationService.initAndSync(meds);
    expect(NotificationService.enabled.value, isNull);
    center.pending.clear();

    center.permissionReadFails = false;
    await NotificationService.refreshPermission();

    expect(NotificationService.enabled.value, isTrue);
    expect(center.alarms, ['매일 08:00 드실 약이 있어요.']);
  });
}
