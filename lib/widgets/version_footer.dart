import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class VersionFooter extends StatelessWidget {
  const VersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    const version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        'v$version · 강대종',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textFaint,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
