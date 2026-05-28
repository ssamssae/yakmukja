import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/widgets/version_footer.dart';

void main() {
  testWidgets('VersionFooter renders "v<APP_VERSION> · 강대종"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VersionFooter())),
    );

    const expectedVersion =
        String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
    expect(find.text('v$expectedVersion · 강대종'), findsOneWidget);
  });
}
