import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

class VersionFooter extends StatelessWidget {
  const VersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    // 버전은 package_info_plus 로 런타임에 pubspec 버전을 읽는다
    // (dart-define APP_VERSION 의존 제거 → 'vdev' footgun 방지).
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '';
        final label = version.isEmpty ? '강대종' : 'v$version · 강대종';
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textFaint,
              letterSpacing: -0.1,
            ),
          ),
        );
      },
    );
  }
}
