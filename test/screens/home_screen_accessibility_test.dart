import 'package:flutter_test/flutter_test.dart';
import 'package:yakmukja/screens/home_screen.dart';

void main() {
  test('taken button semantics label includes medicine, time, and action', () {
    const prefix = '비타민 오전 9:00';

    expect(
      takenButtonSemanticsLabel(prefix: prefix, taken: false),
      '비타민 오전 9:00 복용 완료로 표시',
    );
    expect(
      takenButtonSemanticsLabel(prefix: prefix, taken: true),
      '비타민 오전 9:00 복용 완료 취소',
    );
  });
}
