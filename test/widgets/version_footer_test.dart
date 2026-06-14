import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yakmukja/widgets/version_footer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'yakmukja',
      packageName: 'com.ssamssae.yakmukja',
      version: '9.9.9',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('VersionFooter renders "v<version> · 강대종 마이너스베타스튜디오"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VersionFooter())),
    );
    await tester.pumpAndSettle();

    expect(find.text('v9.9.9 · 강대종 마이너스베타스튜디오'), findsOneWidget);
  });
}
