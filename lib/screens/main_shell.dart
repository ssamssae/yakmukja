import 'package:flutter/material.dart';

import '../services/ads_service.dart';
import '../theme/app_theme.dart';
import '../widgets/version_footer.dart';
import 'home_screen.dart';
import 'medicine_edit_screen.dart';
import 'settings_screen.dart';

/// 앱 쉘 — 하단 푸터 탭바(약목록 / 약등록 / 설정)가 모든 화면에서 상시 유지된다.
/// 약목록·설정은 IndexedStack 으로 전환하고, 약등록은 등록 폼을 push 한다.
/// (T-260614-12, 아니키 요청: 우상단 설정 아이콘·떠있는 약등록 FAB 제거)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 0 = 약목록, 2 = 설정 (1 = 약등록은 push 액션이라 선택 상태 없음)
  int _navIndex = 0;

  static const _tabs = [
    _TabSpec(icon: Icons.medication_outlined, label: '약목록'),
    _TabSpec(icon: Icons.add_circle_outline, label: '약등록'),
    _TabSpec(icon: Icons.settings_outlined, label: '설정'),
  ];

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MedicineEditScreen()),
    );
    if (mounted) setState(() => _navIndex = 0); // 등록 후 약목록으로 복귀
  }

  void _onTap(int i) {
    if (i == 1) {
      _openRegister();
    } else {
      setState(() => _navIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _navIndex == 2 ? 1 : 0,
        children: const [
          HomeScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VersionFooter(),
          const AdaptiveBanner(),
          _BottomTabBar(index: _navIndex, tabs: _tabs, onTap: _onTap),
        ],
      ),
    );
  }
}

class _TabSpec {
  final IconData icon;
  final String label;
  const _TabSpec({required this.icon, required this.label});
}

class _BottomTabBar extends StatelessWidget {
  final int index;
  final List<_TabSpec> tabs;
  final ValueChanged<int> onTap;
  const _BottomTabBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              for (int i = 0; i < tabs.length; i++)
                Expanded(
                  child: _Tab(
                    icon: tabs[i].icon,
                    label: tabs[i].label,
                    selected: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textFaint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
