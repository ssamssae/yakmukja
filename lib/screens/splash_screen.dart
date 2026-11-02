import 'package:flutter/material.dart';

import '../theme/renewal_theme.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String logoAssetPath = 'assets/images/logo.png';
  static const Key iconKey = Key('splash-app-icon');

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 네이티브 시작 화면은 흰 바탕이다. 같은 흰 바탕 가운데에 앱 아이콘을 바로 그려
    // 색이 바뀌는 깜빡임을 막는다. 1.5초 뒤 홈으로 페이드한다.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondary) => const MainShell(),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Semantics(
          label: '약먹자',
          image: true,
          child: ClipRRect(
            key: SplashScreen.iconKey,
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              SplashScreen.logoAssetPath,
              width: 120,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                width: 120,
                height: 120,
                color: RenewalColors.green50,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.medication_rounded,
                  size: 72,
                  color: RenewalColors.green,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
