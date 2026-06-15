import 'package:flutter/material.dart';

/// 약먹자 디자인 시스템 (라이트). 더치페이와 같은 구조, 포인트 컬러만 다름(틸).
/// 색·간격·라운드 토큰을 한 곳에 모아 화면 코드에서 직접 hex 박지 않도록 한다.
class AppColors {
  AppColors._();

  // 베이스 (목업 클린 클리니컬 톤)
  static const bg = Color(0xFFF2F4F6); // scaffold 오프화이트
  static const surface = Color(0xFFFFFFFF); // 카드
  static const shadow = Color(0x0A000000); // black 4% — 옅은 카드 그림자

  // 포인트 (약먹자 = 그린, 새 앱 아이콘과 통일)
  static const primary = Color(0xFF22C55E);
  static const primaryDark = Color(0xFF16A34A); // 텍스트/대비용
  static Color get primarySoft => primary.withValues(alpha: 0.12);

  // 텍스트 (목업 클린 클리니컬 톤)
  static const textStrong = Color(0xFF191F28);
  static const textBody = Color(0xFF4B5563);
  static const textFaint = Color(0xFF8B95A1);

  // 상태 (완료 = green, primary 와 동일 계열로 통일)
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);

  // 클린 클리니컬 토큰 (목업 /tmp/yak-mockup-B.html)
  static const line = Color(0xFFEAEDF0); // 리스트 행 구분선
  static const greenSoft = Color(0xFFECFBF1); // 그린 아이콘칩 배경
  static const trackGrey = Color(0xFFE5E8EB); // 진행바 트랙
  static const chipGrey = Color(0xFFF2F4F6); // 대기 아이콘칩 배경
  static const accent = Color(0xFF3182F6); // "예정" 배지 텍스트
  static const accentSoft = Color(0xFFEAF2FE); // "예정" 배지 배경
}

/// 간격 스케일 (4·8·12·16·20·24)
class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

class AppRadius {
  AppRadius._();
  static const card = 22.0;
  static const button = 14.0;
  static const input = 12.0;
  static const chip = 12.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColors.surface,
      primary: AppColors.primary,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: AppColors.textStrong,
        displayColor: AppColors.textStrong,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textStrong,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 1.5,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// 흰 카드 + 옅은 그림자 (Material Card 대신 직접 그릴 때 공용 데코)
BoxDecoration appCardDecoration({Color? color, BorderRadius? radius}) {
  return BoxDecoration(
    color: color ?? AppColors.surface,
    borderRadius: radius ?? BorderRadius.circular(AppRadius.card),
    boxShadow: const [
      BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 2)),
    ],
  );
}
