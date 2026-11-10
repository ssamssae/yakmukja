import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 리뉴얼 「다음 약 먼저」 색. 기존 토큰과 같은 값은 [AppColors] 를 가리킨다.
class RenewalColors {
  RenewalColors._();

  static const green = AppColors.primary;
  static const greenDeep = AppColors.primaryDark;
  static const green50 = Color(0xFFEAFBF0);
  static const ink = AppColors.textStrong;
  static const body = AppColors.textBody;
  static const faint = AppColors.textFaint;
  static const hush = Color(0xFFB0B8C1);
  static const ring = Color(0xFFD5DAE0);
  static const line = Color(0xFFEEF0F3);
  static const fill = AppColors.bg;
  static const page = Color(0xFFF3F5F7);
  static const date = Color(0xFF3E6E57);
  static const dockMuted = Color(0xFF7D8793);
  static const mintTop = Color(0xFFC2F1D8);
  static const mintMid = Color(0xFFE0F7EA);
  static const blobRight = Color(0xFF9DEBD3);
  static const blobLeft = Color(0xFFBDF5CC);

  /// 지난 약 같은 주의 표시. (T-261110-033)
  static const danger = AppColors.danger;
  static const danger50 = Color(0xFFFFEEEE);
}

class RenewalRadius {
  RenewalRadius._();

  static const nowCard = 32.0;
  static const restCard = 24.0;
  static const button = 20.0;
  static const dock = 33.0;
  static const tag = 10.0;
}

/// 프리텐다드. 자간 기본값 = 글자 크기의 -2.2%.
TextStyle renewalStyle(
  double size,
  FontWeight weight,
  Color color, {
  double? spacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: spacing ?? -size * 0.022,
    height: height,
  );
}

const renewalNowShadows = <BoxShadow>[
  BoxShadow(color: Color(0x2615803D), blurRadius: 44, offset: Offset(0, 18)),
  BoxShadow(color: Color(0x0A191F28), blurRadius: 6, offset: Offset(0, 2)),
];

const renewalRestShadows = <BoxShadow>[
  BoxShadow(color: Color(0x08191F28), blurRadius: 12, offset: Offset(0, 3)),
];

BoxDecoration renewalCardDecoration({
  double radius = RenewalRadius.restCard,
  List<BoxShadow> shadows = renewalRestShadows,
}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadows,
  );
}
