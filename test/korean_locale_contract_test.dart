import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/main.dart';
import 'package:yakmukja/screens/splash_screen.dart';

/// 약먹자는 한국어 앱이다. 기기와 스토어가 이 앱을 한국어 앱으로 알아야 한다.
/// (T-261110-025 — 앱스토어 지원 언어가 영어로 표시되던 문제)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS 앱 묶음이 한국어를 지원 언어로 선언한다', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    // 선언이 없으면 앱스토어에 지원 언어가 영어로 나오고, 알림 허용 같은
    // 시스템 창이 영어로 뜬다.
    expect(
      plist,
      matches(
        RegExp(r'<key>CFBundleDevelopmentRegion</key>\s*<string>ko</string>'),
      ),
    );
    expect(
      plist,
      matches(
        RegExp(
          r'<key>CFBundleLocalizations</key>\s*<array>\s*<string>ko</string>\s*</array>',
        ),
      ),
    );
  });

  testWidgets('앱의 기본 문구(붙여넣기 등)가 한국어로 나온다', (tester) async {
    await tester.pumpWidget(const YakmukjaApp());
    await tester.pump();

    final context = tester.element(find.byType(SplashScreen));
    expect(Localizations.localeOf(context), const Locale('ko'));
    expect(MaterialLocalizations.of(context).pasteButtonLabel, '붙여넣기');

    // 시작 화면의 1.5초 타이머가 끝나기 전에 화면을 내린다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
