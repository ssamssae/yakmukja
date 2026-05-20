import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/medicine.dart';
import 'screens/splash_screen.dart';
import 'services/ads_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

const String medicineBoxName = 'medicines';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? fatalError;
  try {
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
    // 30일 초과 복용 기록 정리 (무한 누적 방지)
    for (final m in Hive.box<Medicine>(medicineBoxName).values) {
      m.pruneOldRecords();
    }
  } catch (e, st) {
    debugPrint('[main] Hive init fatal: $e\n$st');
    fatalError = e;
  }

  // NotificationService 는 내부에서 예외를 흡수하도록 설계됨
  await NotificationService.init();
  await AdsService.init();

  runApp(fatalError == null
      ? const YakmukjaApp()
      : _FatalErrorApp(error: fatalError));
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
                const Icon(Icons.error_outline, color: AppColors.primary, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '앱을 시작할 수 없어요',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textStrong),
                ),
                const SizedBox(height: 8),
                const Text(
                  '저장소 초기화 중 오류가 발생했습니다. 앱을 재실행해 주세요.',
                  style: TextStyle(color: AppColors.textBody),
                ),
                const SizedBox(height: 16),
                Text(
                  '$error',
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
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
