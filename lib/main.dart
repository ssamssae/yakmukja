import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/medicine.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

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
  } catch (e, st) {
    debugPrint('[main] Hive init fatal: $e\n$st');
    fatalError = e;
  }

  // NotificationService 는 내부에서 예외를 흡수하도록 설계됨
  await NotificationService.init();

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
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFFFC107), size: 48),
                const SizedBox(height: 16),
                const Text(
                  '앱을 시작할 수 없어요',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  '저장소 초기화 중 오류가 발생했습니다. 앱을 재실행해 주세요.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Text(
                  '$error',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
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
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFC107),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFFC107), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          elevation: 2,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
