import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 약 모양 그림. 시안 2번의 캡슐·젤·스틱을 화면에서 같이 쓴다.

enum PillKind { capsule, softgel, sachet }

/// 약마다 다른 알약 그림 색.
class PillLook {
  const PillLook({
    required this.kind,
    required this.body,
    required this.cap,
    required this.soft,
    required this.deep,
  });

  final PillKind kind;
  final Color body; // 몸통(진한 쪽)
  final Color cap; // 반대쪽 캡 · 밝은 빛
  final Color soft; // 아이콘 원 · 타일 바탕
  final Color deep; // 그늘 · 강조 글자

  static const vitaminD = PillLook(
    kind: PillKind.capsule,
    body: Color(0xFFFF7B5C),
    cap: Color(0xFFFFE6C7),
    soft: Color(0xFFFFEEE8),
    deep: Color(0xFFE2583A),
  );
  static const omega3 = PillLook(
    kind: PillKind.softgel,
    body: Color(0xFFF6B12B),
    cap: Color(0xFFFFE9A6),
    soft: Color(0xFFFFF4D9),
    deep: Color(0xFFD08508),
  );
  static const probiotic = PillLook(
    kind: PillKind.sachet,
    body: Color(0xFF7F8CF9),
    cap: Color(0xFFFFFFFF),
    soft: Color(0xFFECEEFF),
    deep: Color(0xFF5B66DD),
  );
  // 앱 아이콘(웃는 캡슐) 색.
  static const mascot = PillLook(
    kind: PillKind.capsule,
    body: Color(0xFFEF7A5E),
    cap: Color(0xFFF6E3C8),
    soft: Color(0xFFD9E8F7),
    deep: Color(0xFFD45C40),
  );

  static const palette = <PillLook>[
    vitaminD,
    omega3,
    probiotic,
    PillLook(
      kind: PillKind.capsule,
      body: Color(0xFF3DDC97),
      cap: Color(0xFFE7FFF4),
      soft: Color(0xFFE5FBF1),
      deep: Color(0xFF14915A),
    ),
    PillLook(
      kind: PillKind.softgel,
      body: Color(0xFF5B8DEF),
      cap: Color(0xFFD6E4FF),
      soft: Color(0xFFE7F0FF),
      deep: Color(0xFF2F62C4),
    ),
    PillLook(
      kind: PillKind.sachet,
      body: Color(0xFFF472B6),
      cap: Color(0xFFFFFFFF),
      soft: Color(0xFFFDE7F1),
      deep: Color(0xFFDB2777),
    ),
  ];
}

/// 약 모양 그림(캡슐 · 젤 캡슐 · 스틱 포). face = 앱 아이콘처럼 웃는 얼굴.
class PillGlyph extends StatelessWidget {
  const PillGlyph({
    super.key,
    required this.look,
    this.size = 28,
    this.face = false,
    this.shadow = false,
    this.tilt,
  });

  final PillLook look;
  final double size;
  final bool face;
  final bool shadow;
  final double? tilt;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PillPainter(look, face: face, shadow: shadow, tilt: tilt),
      ),
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter(
    this.look, {
    required this.face,
    required this.shadow,
    this.tilt,
  });

  final PillLook look;
  final bool face;
  final bool shadow;
  final double? tilt;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (shadow) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, s * 0.43),
          width: s * 0.60,
          height: s * 0.10,
        ),
        Paint()
          ..color = const Color(0x24000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.035),
      );
    }
    switch (look.kind) {
      case PillKind.capsule:
        _capsule(canvas, s);
      case PillKind.softgel:
        _softgel(canvas, s);
      case PillKind.sachet:
        _sachet(canvas, s);
    }
    canvas.restore();
  }

  void _capsule(Canvas canvas, double s) {
    final angle = tilt ?? -0.70;
    final len = s * 0.90;
    final w = s * 0.40;
    canvas.save();
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: len, height: w);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(w / 2));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(
      Rect.fromLTRB(-len / 2, -w / 2, 0, w / 2),
      Paint()..color = look.body,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, -w / 2, len / 2, w / 2),
      Paint()..color = look.cap,
    );
    // 둥근 몸통 음영: 위는 밝게, 아래는 살짝 어둡게.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x40FFFFFF), Color(0x00FFFFFF), Color(0x1F000000)],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(0, -w / 2),
      Offset(0, w / 2),
      Paint()
        ..color = const Color(0x1F000000)
        ..strokeWidth = math.max(0.8, s * 0.012),
    );
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          -len / 2 + w * 0.34,
          -w / 2 + w * 0.15,
          len / 2 - w * 0.34,
          -w / 2 + w * 0.29,
        ),
        Radius.circular(w * 0.08),
      ),
      Paint()..color = const Color(0x99FFFFFF),
    );
    if (face) _face(canvas, Offset(len * 0.22, w * 0.03), w, angle);
    canvas.restore();
  }

  void _softgel(Canvas canvas, double s) {
    final angle = tilt ?? -0.55;
    final w = s * 0.86;
    final h = s * 0.54;
    canvas.save();
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.6),
          radius: 1.05,
          colors: [look.cap, look.body, look.deep],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect.deflate(s * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, s * 0.014)
        ..color = look.deep.withValues(alpha: 0.28),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-w * 0.12, -h * 0.23),
        width: w * 0.44,
        height: h * 0.20,
      ),
      Paint()..color = const Color(0xB3FFFFFF),
    );
    canvas.drawCircle(
      Offset(w * 0.24, -h * 0.17),
      h * 0.05,
      Paint()..color = const Color(0x80FFFFFF),
    );
    if (face) _face(canvas, Offset(0, h * 0.12), h * 0.80, angle);
    canvas.restore();
  }

  void _sachet(Canvas canvas, double s) {
    final angle = tilt ?? -0.38;
    final w = s * 0.46;
    final h = s * 0.88;
    final crimp = h * 0.13;
    final amp = s * 0.02;
    const teeth = 7;
    canvas.save();
    canvas.rotate(angle);
    // 위아래 톱니 가장자리를 가진 스틱 포.
    final path = Path()..moveTo(-w / 2, -h / 2 + amp);
    for (var i = 0; i < teeth; i++) {
      final x0 = -w / 2 + w * i / teeth;
      path
        ..lineTo(x0 + w / teeth / 2, -h / 2)
        ..lineTo(x0 + w / teeth, -h / 2 + amp);
    }
    path.lineTo(w / 2, h / 2 - amp);
    for (var i = teeth; i > 0; i--) {
      final x0 = -w / 2 + w * i / teeth;
      path
        ..lineTo(x0 - w / teeth / 2, h / 2)
        ..lineTo(x0 - w / teeth, h / 2 - amp);
    }
    path.close();
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(look.body, Colors.white, 0.20)!,
            look.body,
            look.deep,
          ],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );
    final band = Paint()..color = look.deep.withValues(alpha: 0.30);
    canvas.drawRect(
      Rect.fromLTRB(-w / 2, -h / 2 + amp, w / 2, -h / 2 + crimp),
      band,
    );
    canvas.drawRect(
      Rect.fromLTRB(-w / 2, h / 2 - crimp, w / 2, h / 2 - amp),
      band,
    );
    final rib = Paint()
      ..color = const Color(0x47FFFFFF)
      ..strokeWidth = math.max(0.6, s * 0.01);
    for (var i = 1; i < 6; i++) {
      final x = -w / 2 + w * i / 6;
      canvas.drawLine(
        Offset(x, -h / 2 + amp * 1.6),
        Offset(x, -h / 2 + crimp - amp * 0.6),
        rib,
      );
      canvas.drawLine(
        Offset(x, h / 2 - crimp + amp * 0.6),
        Offset(x, h / 2 - amp * 1.6),
        rib,
      );
    }
    final labelCenter = Offset(0, h * 0.02);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: labelCenter, width: w * 0.72, height: h * 0.38),
        Radius.circular(s * 0.05),
      ),
      Paint()..color = look.cap.withValues(alpha: 0.94),
    );
    if (face) {
      _face(canvas, labelCenter + Offset(0, h * 0.01), w * 0.60, angle);
    } else {
      canvas.drawCircle(
        labelCenter - Offset(0, h * 0.05),
        w * 0.12,
        Paint()..color = look.body.withValues(alpha: 0.60),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: labelCenter + Offset(0, h * 0.095),
            width: w * 0.40,
            height: math.max(1.2, h * 0.04),
          ),
          Radius.circular(s),
        ),
        Paint()..color = look.body.withValues(alpha: 0.38),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          -w / 2 + w * 0.08,
          -h / 2 + crimp + h * 0.03,
          -w / 2 + w * 0.17,
          h / 2 - crimp - h * 0.03,
        ),
        Radius.circular(s),
      ),
      Paint()..color = const Color(0x40FFFFFF),
    );
    canvas.restore();
  }

  // 앱 아이콘의 웃는 얼굴. 몸통 기울기를 풀고 살짝만 기울여 그린다.
  void _face(Canvas canvas, Offset at, double unit, double angle) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(-angle - 0.10);
    const ink = Color(0xFF2A2A30);
    final eyeR = unit * 0.075;
    final gap = unit * 0.20;
    final eye = Paint()..color = ink;
    canvas.drawCircle(Offset(-gap, -unit * 0.05), eyeR, eye);
    canvas.drawCircle(Offset(gap, -unit * 0.05), eyeR, eye);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(0, unit * 0.0), radius: unit * 0.10),
      0.45,
      math.pi - 0.9,
      false,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.055
        ..strokeCap = StrokeCap.round,
    );
    final blush = Paint()..color = const Color(0x59FF7F86);
    for (final dx in [-gap * 1.65, gap * 1.65]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(dx, unit * 0.07),
          width: unit * 0.17,
          height: unit * 0.09,
        ),
        blush,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      old.look != look ||
      old.face != face ||
      old.shadow != shadow ||
      old.tilt != tilt;
}

/// 시안 샘플 이름은 시안과 같은 그림을 쓰고, 그 밖은 이름마다 같은 그림을 고른다.
PillLook lookForMedicineName(String name) {
  switch (name.trim()) {
    case '비타민D':
      return PillLook.vitaminD;
    case '오메가3':
      return PillLook.omega3;
    case '유산균':
      return PillLook.probiotic;
    default:
      var hash = 0;
      for (final unit in name.codeUnits) {
        hash = (hash * 33 + unit) & 0x7fffffff;
      }
      return PillLook.palette[hash % PillLook.palette.length];
  }
}
