import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/screens/medicine_edit_screen.dart';
import 'package:yakmukja/theme/app_theme.dart';
import 'package:yakmukja/widgets/renewal_dock.dart';

/// 접근성 최대 글자(배율 3.12)와 보통 글자에서
/// 홈 아래 메뉴와 약 등록 화면이 칸 밖으로 넘치지 않는다.
/// (T-261111-042)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widths = <double>[375, 402];
  const scales = <double>[1, 3.12];

  Future<void> setSurface(
    WidgetTester tester, {
    required double width,
    required double textScale,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  List<Object> takeErrors(WidgetTester tester) {
    final errors = <Object>[];
    while (true) {
      final error = tester.takeException();
      if (error == null) return errors;
      errors.add(error);
    }
  }

  Finder dockBar() {
    return find
        .descendant(
          of: find.byType(RenewalDock),
          matching: find.byType(Container),
        )
        .first;
  }

  group('홈 아래 메뉴', () {
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('폭 $width·글씨 $scale배에서 메뉴 글자가 칸 안에 있다', (tester) async {
          await setSurface(tester, width: width, textScale: scale);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: SizedBox.expand(),
                bottomNavigationBar: RenewalDock(index: 0),
              ),
            ),
          );
          await tester.pump();

          expect(takeErrors(tester), isEmpty);
          final bar = tester.getRect(dockBar());
          if (scale == 1) {
            expect(bar.height, 66);
          } else {
            expect(bar.height, greaterThanOrEqualTo(66));
          }
          for (final label in ['약목록', '약등록', '설정']) {
            expect(find.text(label), findsOneWidget);
            final rect = tester.getRect(find.text(label));
            expect(
              rect.left,
              greaterThanOrEqualTo(bar.left - 0.1),
              reason: label,
            );
            expect(
              rect.right,
              lessThanOrEqualTo(bar.right + 0.1),
              reason: label,
            );
            expect(
              rect.top,
              greaterThanOrEqualTo(bar.top - 0.1),
              reason: label,
            );
            expect(
              rect.bottom,
              lessThanOrEqualTo(bar.bottom + 0.1),
              reason: label,
            );
          }
        });
      }
    }
  });

  group('약 등록', () {
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('폭 $width·글씨 $scale배에서 제목·요일·저장이 칸 안에 있다', (tester) async {
          await setSurface(tester, width: width, textScale: scale);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: const MedicineEditScreen(),
            ),
          );
          await tester.pump();

          expect(takeErrors(tester), isEmpty);

          final title = tester.getRect(find.text('복용량'));
          final hint = tester.getRect(find.text('(선택)').first);
          final card = tester.getRect(
            find
                .ancestor(
                  of: find.text('복용량'),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(title.left, greaterThanOrEqualTo(card.left - 0.1));
          expect(title.right, lessThanOrEqualTo(card.right + 0.1));
          expect(hint.left, greaterThanOrEqualTo(card.left - 0.1));
          expect(hint.right, lessThanOrEqualTo(card.right + 0.1));
          if (scale == 1) {
            expect((title.center.dy - hint.center.dy).abs(), lessThan(2));
          }

          for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
            final text = tester.renderObject<RenderParagraph>(find.text(label));
            expect(text.debugHasOverflowShader, isFalse, reason: label);
            final circle = tester.getRect(
              find
                  .ancestor(of: find.text(label), matching: find.byType(Ink))
                  .first,
            );
            final glyph = tester.getRect(find.text(label));
            expect(
              glyph.left,
              greaterThanOrEqualTo(circle.left - 0.1),
              reason: label,
            );
            expect(
              glyph.right,
              lessThanOrEqualTo(circle.right + 0.1),
              reason: label,
            );
            expect(
              glyph.top,
              greaterThanOrEqualTo(circle.top - 0.1),
              reason: label,
            );
            expect(
              glyph.bottom,
              lessThanOrEqualTo(circle.bottom + 0.1),
              reason: label,
            );
          }
          if (scale == 1) {
            final top = tester.getRect(find.text('월')).center.dy;
            expect(
              (tester.getRect(find.text('일')).center.dy - top).abs(),
              lessThan(1),
            );
          }

          final save = tester.renderObject<RenderParagraph>(find.text('저장'));
          expect(save.debugHasOverflowShader, isFalse);
          final button = tester.getRect(
            find
                .ancestor(of: find.text('저장'), matching: find.byType(Ink))
                .first,
          );
          final saveRect = tester.getRect(find.text('저장'));
          expect(saveRect.top, greaterThanOrEqualTo(button.top - 0.1));
          expect(saveRect.bottom, lessThanOrEqualTo(button.bottom + 0.1));
          expect(saveRect.left, greaterThanOrEqualTo(button.left - 0.1));
          expect(saveRect.right, lessThanOrEqualTo(button.right + 0.1));
          if (scale == 1) {
            expect(button.height, 60);
          } else {
            expect(button.height, greaterThanOrEqualTo(60));
          }
        });
      }
    }
  });
}
