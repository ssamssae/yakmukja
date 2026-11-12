import 'package:flutter/material.dart';

import '../theme/renewal_theme.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const String logoAssetPath = 'assets/images/logo.png';
  static const Key iconKey = Key('splash-app-icon');
  static const Key nameKey = Key('splash-app-name');
  static const String appName = '약먹자';

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
    // 앱 아이콘(초록 바탕 흰 「약」) 아래에 앱 이름을 함께 보여 준다.
    // 아이콘과 이름을 한 묶음으로 화면 가운데에 둔다. (T-261112-035)
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                image: true,
                child: ClipRRect(
                  key: SplashScreen.iconKey,
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    SplashScreen.logoAssetPath,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
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
              const SizedBox(height: 16),
              Text(
                SplashScreen.appName,
                key: SplashScreen.nameKey,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: renewalStyle(26, FontWeight.w800, RenewalColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
