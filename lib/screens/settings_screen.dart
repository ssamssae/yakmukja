import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 설정 화면. 현재는 "피드백 보내기"(mailto) 진입점만 둔다. (T-260614-14)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String feedbackEmail = 'minusbetastudio@gmail.com';

  Future<void> _sendFeedback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    // 앱 버전 + OS 정보를 본문에 prefill (문제 재현·대응용). 사용자가 지워도 무방.
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'v${info.version} (${info.buildNumber})';
    } catch (_) {}
    final device = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
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
      messenger.showSnackBar(
        const SnackBar(
          content: Text('메일 앱을 열 수 없어요. $feedbackEmail 으로 보내주세요.'),
        ),
      );
    }
  }

  // Uri(queryParameters:) 는 공백을 '+' 로 인코딩해 일부 메일 앱에서 깨진다.
  // mailto 본문은 %20 인코딩이 안전하므로 직접 인코딩한다.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map(
        (e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(
              Icons.feedback_outlined,
              color: AppColors.primary,
            ),
            title: const Text('피드백 보내기'),
            subtitle: const Text('의견·버그 제보를 메일로 보내요'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _sendFeedback(context),
          ),
        ],
      ),
    );
  }
}
