import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android edge-to-edge release contract', () {
    test('requires the Flutter embedding with Android 15 API guards', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(
        pubspec,
        matches(RegExp(r'^  flutter: ">=3\.44\.0"$', multiLine: true)),
      );
    });

    test('enables edge-to-edge before app startup', () {
      final source = File('lib/main.dart').readAsStringSync();
      final bindingIndex = source.indexOf(
        'WidgetsFlutterBinding.ensureInitialized();',
      );
      final edgeToEdgeIndex = source.indexOf(
        'await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);',
      );
      final runAppIndex = source.indexOf('runApp(');

      expect(source, contains("import 'package:flutter/services.dart';"));
      expect(bindingIndex, greaterThanOrEqualTo(0));
      expect(edgeToEdgeIndex, greaterThan(bindingIndex));
      expect(edgeToEdgeIndex, lessThan(runAppIndex));
    });

    test('does not restore deprecated display-cutout parameters', () {
      const styleFiles = <String>[
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ];

      for (final path in styleFiles) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          isNot(contains('android:windowLayoutInDisplayCutoutMode')),
          reason: path,
        );
        expect(source, isNot(contains('shortEdges')), reason: path);
      }
    });
  });
}
