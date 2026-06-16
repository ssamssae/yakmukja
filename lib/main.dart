import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'config.dart';
import 'models/medicine.dart';
import 'screens/splash_screen.dart';
import 'services/ads_service.dart';
import 'services/iap_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

const String medicineBoxName = 'medicines';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? fatalError;
  try {
    await _initLocalStore();
  } catch (e, st) {
    debugPrint('[main] Hive init fatal: $e\n$st');
    fatalError = e;
  }

  runApp(
    fatalError == null
        ? const YakmukjaApp()
        : _FatalErrorApp(error: fatalError),
  );

  if (fatalError == null) {
    _startDeferredColdStartWork();
  }
}

Future<void> _initLocalStore() async {
  await Hive.initFlutter();
  Hive.registerAdapter(MedicineAdapter());
  Hive.registerAdapter(DoseTimeAdapter());
  try {
    await Hive.openBox<Medicine>(medicineBoxName);
  } catch (e, st) {
    debugPrint('[main] openBox failed, deleting corrupted box: $e\n$st');
    await Hive.deleteBoxFromDisk(medicineBoxName);
    await Hive.openBox<Medicine>(medicineBoxName);
  }
  if (kScreenshotSeed) {
    await _seedScreenshotData();
  }
}

/// 스토어 스크린샷용 샘플 약. 보관함이 비어 있을 때만 넣는다.
Future<void> _seedScreenshotData() async {
  final box = Hive.box<Medicine>(medicineBoxName);
  if (box.isNotEmpty) return;
  final now = DateTime.now();
  await box.addAll([
    Medicine(
      name: '비타민D',
      dosage: '1알',
      times: [DoseTime(hour: 8, minute: 0)],
      memo: '',
      createdAt: now,
    ),
    Medicine(
      name: '오메가3',
      dosage: '2알',
      times: [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 0)],
      memo: '',
      createdAt: now,
    ),
    Medicine(
      name: '유산균',
      dosage: '1알',
      times: [DoseTime(hour: 21, minute: 30)],
      memo: '',
      createdAt: now,
    ),
  ]);
}

void _startDeferredColdStartWork() {
  unawaited(
    Future<void>(() async {
      await _runDeferredStartupStep('pruneOldRecords', () {
        // 30일 초과 복용 기록 정리 (무한 누적 방지). 첫 프레임 이후로 미뤄
        // cold-start 흰 화면 시간을 늘리지 않는다.
        // 휴지통 30일 경과분도 함께 영구 삭제. (T-260614-12)
        final cutoff = DateTime.now().subtract(Medicine.trashRetention);
        for (final m in Hive.box<Medicine>(medicineBoxName).values.toList()) {
          m.pruneOldRecords();
          if (m.deletedAt != null && m.deletedAt!.isBefore(cutoff)) {
            m.delete();
          }
        }
      });
      await _runDeferredStartupStep('IapService.init', IapService.init);
      if (!kScreenshotMode) {
        // 스토어 스크린샷 캡처 시 알림권한 다이얼로그·광고 로드를 끈다.
        await _runDeferredStartupStep(
          'NotificationService.init',
          NotificationService.init,
        );
        await _runDeferredStartupStep('AdsService.init', AdsService.init);
      }
    }),
  );
}

Future<void> _runDeferredStartupStep(
  String label,
  FutureOr<void> Function() action,
) async {
  try {
    await action();
  } catch (e, st) {
    debugPrint('[main] deferred $label failed: $e\n$st');
  }
}

class _FatalErrorApp extends StatelessWidget {
  final Object error;
  const _FatalErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.primary,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  '앱을 시작할 수 없어요',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '저장소 초기화 중 오류가 발생했습니다. 앱을 재실행해 주세요.',
                  style: TextStyle(color: AppColors.textBody),
                ),
                const SizedBox(height: 16),
                Text(
                  '$error',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class YakmukjaApp extends StatelessWidget {
  const YakmukjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '약먹자',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
