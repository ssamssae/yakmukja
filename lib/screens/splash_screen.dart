import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String logoAssetPath = 'assets/images/logo.png';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 네이티브 런치스크린(flutter_native_splash, 동일 로고/배경)에서 이어받으므로
    // 진입 fade-in 없이 즉시 동일 화면을 그려 handoff 깜빡임을 막는다.
    // 총 체류 1.5초 후 홈으로 페이드아웃. (T-260614-11 (A))
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondary) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 네이티브 런치스크린(flutter_native_splash)과 완전히 동일하게 로고만
    // 64pt, 동일 배경(#F7F8FA)으로 그려 네이티브→Flutter handoff 를 한 화면처럼
    // 이어지게 한다. 둥근 박스/그림자/타이틀 텍스트를 두면 네이티브와 달라
    // "splash 2개"로 보이므로 제거. (T-260614-15)
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Image.asset(
          SplashScreen.logoAssetPath,
          width: 64,
          height: 64,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Icon(
            Icons.medication_rounded,
            size: 64,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
