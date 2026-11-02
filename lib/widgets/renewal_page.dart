import 'package:flutter/material.dart';

import '../theme/renewal_theme.dart';

/// 민트 머리. 홈·약 등록과 같은 그라데이션이다.
class RenewalBackdrop extends StatelessWidget {
  const RenewalBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                RenewalColors.mintTop,
                RenewalColors.mintMid,
                RenewalColors.page,
              ],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          top: -140,
          right: -110,
          child: _Blob(size: 360, color: RenewalColors.blobRight),
        ),
        Positioned(
          top: 70,
          left: -150,
          child: _Blob(size: 320, color: RenewalColors.blobLeft),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// 설정·휴지통·정책이 같이 쓰는 페이지. 뒤로가기는 쌓인 화면만 둔다.
class RenewalPage extends StatelessWidget {
  const RenewalPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: RenewalColors.page,
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 360,
            child: RenewalBackdrop(),
          ),
          ListView(
            padding: EdgeInsets.fromLTRB(20, top + 12, 20, 24 + bottom),
            children: [
              RenewalPageHeader(
                title: title,
                subtitle: subtitle,
                onBack: onBack,
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ],
      ),
    );
  }
}

class RenewalPageHeader extends StatelessWidget {
  const RenewalPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onBack != null) ...[
              Tooltip(
                message: '뒤로',
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: RenewalColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: renewalStyle(28, FontWeight.w800, RenewalColors.ink),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: renewalStyle(15, FontWeight.w600, RenewalColors.body),
          ),
        ],
      ],
    );
  }
}

class RenewalSectionLabel extends StatelessWidget {
  const RenewalSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: renewalStyle(13, FontWeight.w700, RenewalColors.faint),
      ),
    );
  }
}

/// 흰 카드 안의 설정 줄.
class RenewalMenuCard extends StatelessWidget {
  const RenewalMenuCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          const Divider(
            height: 1,
            thickness: 1,
            indent: 68,
            endIndent: 16,
            color: RenewalColors.line,
          ),
        );
      }
    }
    return DecoratedBox(
      decoration: renewalCardDecoration(),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RenewalRadius.restCard),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

class RenewalMenuRow extends StatelessWidget {
  const RenewalMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: RenewalColors.green50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: RenewalColors.greenDeep),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: renewalStyle(16, FontWeight.w700, RenewalColors.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: renewalStyle(
                        13,
                        FontWeight.w600,
                        RenewalColors.faint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: RenewalColors.hush),
          ],
        ),
      ),
    );
  }
}
