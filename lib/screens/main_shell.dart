import 'package:flutter/material.dart';

import '../services/ads_service.dart';
import '../theme/renewal_theme.dart';
import '../widgets/renewal_dock.dart';
import '../widgets/version_footer.dart';
import 'home_screen.dart';
import 'medicine_edit_screen.dart';
import 'settings_screen.dart';

/// 앱 쉘 — 검은 둥근 탭바(약목록 / 약등록 / 설정)가 모든 화면에서 상시 유지된다.
/// 약목록·설정은 IndexedStack 으로 전환하고, 약등록은 등록 폼을 push 한다.
/// (T-260614-12, 우상단 설정 아이콘·떠있는 약등록 FAB 제거)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // 0 = 약목록, 2 = 설정 (1 = 약등록은 push 액션이라 선택 상태 없음)
  int _navIndex = 0;

  Future<void> _openRegister() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MedicineEditScreen()));
    if (mounted) setState(() => _navIndex = 0);
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
      backgroundColor: RenewalColors.page,
      body: IndexedStack(
        index: _navIndex == 2 ? 1 : 0,
        children: const [HomeScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: ColoredBox(
        color: RenewalColors.page,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VersionFooter(),
              const AdaptiveBanner(),
              RenewalDock(index: _navIndex, onTap: _onTap),
            ],
          ),
        ),
      ),
    );
  }
}
