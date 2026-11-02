import 'package:flutter/material.dart';

import '../theme/renewal_theme.dart';

/// 둥근 복용 체크. 기록은 호출하는 쪽이 기존 저장 함수로 한다.
class RenewalCheck extends StatelessWidget {
  const RenewalCheck({
    super.key,
    required this.taken,
    this.size = 40,
    this.onFill = RenewalColors.green,
    this.onMark = Colors.white,
    this.offFill = Colors.white,
    this.offBorder = RenewalColors.ring,
    this.offMark = RenewalColors.ring,
    this.onTap,
  });

  final bool taken;
  final double size;
  final Color onFill;
  final Color onMark;
  final Color offFill;
  final Color offBorder;
  final Color offMark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: taken ? onFill : offFill,
          border: taken
              ? null
              : Border.all(color: offBorder, width: size >= 36 ? 2 : 1.6),
        ),
        child: Icon(
          Icons.check_rounded,
          size: size * 0.56,
          color: taken ? onMark : offMark,
        ),
      ),
    );
  }
}
