import 'package:flutter/material.dart';

import '../theme/renewal_theme.dart';

/// 검은 둥근 탭바. 가운데 초록 버튼은 약 등록이다.
class RenewalDock extends StatelessWidget {
  const RenewalDock({super.key, required this.index, this.onTap});

  final int index;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
      child: Container(
        // 글자가 커지면 칸이 함께 커진다. 보통 글자에서는 최소 66을 유지한다.
        // (T-261111-042)
        constraints: const BoxConstraints(minHeight: 66),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: RenewalColors.ink,
          borderRadius: BorderRadius.circular(RenewalRadius.dock),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40191F28),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _DockItem(
                icon: Icons.medication_rounded,
                label: '약목록',
                selected: index == 0,
                onTap: onTap == null ? null : () => onTap!(0),
              ),
            ),
            GestureDetector(
              onTap: onTap == null ? null : () => onTap!(1),
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
                decoration: BoxDecoration(
                  color: RenewalColors.green,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '약등록',
                      style: renewalStyle(15, FontWeight.w700, Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _DockItem(
                icon: Icons.settings_rounded,
                label: '설정',
                selected: index == 2,
                onTap: onTap == null ? null : () => onTap!(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : RenewalColors.dockMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: renewalStyle(11.5, FontWeight.w700, color, spacing: -0.2),
          ),
        ],
      ),
    );
  }
}
