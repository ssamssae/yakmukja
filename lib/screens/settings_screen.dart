import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_review_service.dart';
import '../services/iap_service.dart';
import '../theme/app_theme.dart';
import 'policy_screen.dart';
import 'trash_screen.dart';

/// 설정 화면 — 평가 / 피드백 / 광고제거 / 구매복원 / 휴지통 / 약관 / 개인정보.
/// (T-260614-12, 아니키 요청: 메모요식 레이아웃, 백업&복원 제외)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String feedbackEmail = 'minusbetastudio@gmail.com';

  Future<void> _rate(BuildContext context) async {
    final ok = await AppReviewService.openReview();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지금은 평가를 열 수 없어요')),
      );
    }
  }

  Future<void> _sendFeedback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'v${info.version} (${info.buildNumber})';
    } catch (_) {}
    final device =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    final body = '\n\n\n--- 아래 정보는 문제 해결에 도움이 돼요 (지워도 됩니다) ---\n'
        '앱: 약먹자 $version\n'
        '기기: $device';
    final uri = Uri(
      scheme: 'mailto',
      path: feedbackEmail,
      query: _encodeQuery({'subject': '[약먹자] 피드백', 'body': body}),
    );
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('메일 앱을 열 수 없어요')),
      );
    }
  }

  String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          _tile(context,
              icon: Icons.star_rate_outlined,
              label: '앱 평가하기',
              onTap: () => _rate(context)),
          _tile(context,
              icon: Icons.feedback_outlined,
              label: '피드백 보내기',
              onTap: () => _sendFeedback(context)),
          ValueListenableBuilder<bool>(
            valueListenable: IapService.adsRemoved,
            builder: (context, removed, _) {
              if (removed) return const SizedBox.shrink();
              return _tile(context,
                  icon: Icons.block_outlined,
                  label: '광고 제거',
                  iconColor: AppColors.primary,
                  onTap: () async {
                    final result = await IapService.buyRemoveAds();
                    final msg = IapService.purchaseMessage(result);
                    if (msg != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg)),
                      );
                    }
                  });
            },
          ),
          _tile(context,
              icon: Icons.restore,
              label: '구매 복원',
              onTap: () async {
                final ok = await IapService.restorePurchases();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? '구매 내역을 확인했어요.'
                          : '스토어에 연결할 수 없어요. 잠시 후 다시 시도해주세요.'),
                    ),
                  );
                }
              }),
          _tile(context,
              icon: Icons.delete_outline,
              label: '휴지통',
              onTap: () => _push(context, const TrashScreen())),
          _tile(context,
              icon: Icons.description_outlined,
              label: '이용약관',
              onTap: () => _push(
                  context,
                  const PolicyScreen(
                      title: '이용약관',
                      assetPath: 'docs/legal/terms-of-service.md'))),
          _tile(context,
              icon: Icons.privacy_tip_outlined,
              label: '개인정보처리방침',
              onTap: () => _push(
                  context,
                  const PolicyScreen(
                      title: '개인정보처리방침',
                      assetPath: 'docs/legal/privacy-policy.md'))),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? sub,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Icon(icon, color: iconColor ?? theme.colorScheme.onSurface),
          title: Text(label, style: theme.textTheme.bodyLarge),
          subtitle: sub == null
              ? null
              : Text(sub,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
          trailing:
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          onTap: onTap,
        ),
        const Divider(height: 1, thickness: 0.5, indent: 20, endIndent: 20),
      ],
    );
  }
}
