import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_review_service.dart';
import '../services/iap_service.dart';
import '../widgets/renewal_page.dart';
import 'policy_screen.dart';
import 'trash_screen.dart';

/// 설정 — 평가 / 피드백 / 광고제거 / 구매복원 / 휴지통 / 약관 / 개인정보.
/// 광고 제거 구매와 구매 복원 줄은 구매 후에도 남긴다. (애플 심사 3.1.1)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String feedbackEmail = 'minusbetastudio@gmail.com';

  Future<void> _rate(BuildContext context) async {
    final ok = await AppReviewService.openReview();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('지금은 평가를 열 수 없어요')));
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
    final body =
        '\n\n\n--- 아래 정보는 문제 해결에 도움이 돼요 (지워도 됩니다) ---\n'
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
      messenger.showSnackBar(const SnackBar(content: Text('메일 앱을 열 수 없어요')));
    }
  }

  String _encodeQuery(Map<String, String> params) => params.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _buyRemoveAds(BuildContext context) async {
    final result = await IapService.buyRemoveAds();
    final msg = IapService.purchaseMessage(result);
    if (msg != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    final ok = await IapService.restorePurchases();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? '구매 내역을 확인했어요.' : '스토어에 연결할 수 없어요. 잠시 후 다시 시도해주세요.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RenewalPage(
      title: '설정',
      subtitle: '구매와 기록을 여기서 관리해요',
      children: [
        const RenewalSectionLabel('앱'),
        RenewalMenuCard(
          children: [
            RenewalMenuRow(
              icon: Icons.star_rounded,
              label: '앱 평가하기',
              onTap: () => _rate(context),
            ),
            RenewalMenuRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: '피드백 보내기',
              onTap: () => _sendFeedback(context),
            ),
            RenewalMenuRow(
              icon: Icons.delete_outline_rounded,
              label: '휴지통',
              onTap: () => _push(context, const TrashScreen()),
            ),
          ],
        ),
        const RenewalSectionLabel('구매'),
        ValueListenableBuilder<bool>(
          valueListenable: IapService.adsRemoved,
          builder: (context, removed, _) {
            return RenewalMenuCard(
              children: [
                RenewalMenuRow(
                  icon: Icons.block_rounded,
                  label: '광고 제거',
                  subtitle: removed ? '이미 광고가 제거되어 있어요' : null,
                  onTap: () => _buyRemoveAds(context),
                ),
                RenewalMenuRow(
                  icon: Icons.restore_rounded,
                  label: '구매 복원',
                  onTap: () => _restorePurchases(context),
                ),
              ],
            );
          },
        ),
        const RenewalSectionLabel('안내'),
        RenewalMenuCard(
          children: [
            RenewalMenuRow(
              icon: Icons.description_outlined,
              label: '이용약관',
              onTap: () => _push(
                context,
                const PolicyScreen(
                  title: '이용약관',
                  assetPath: 'docs/legal/terms-of-service.md',
                ),
              ),
            ),
            RenewalMenuRow(
              icon: Icons.verified_user_outlined,
              label: '개인정보처리방침',
              onTap: () => _push(
                context,
                const PolicyScreen(
                  title: '개인정보처리방침',
                  assetPath: 'docs/legal/privacy-policy.md',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
