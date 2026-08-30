import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/difficulty.dart';

void main() {
  test('labels and storage keys are stable', () {
    expect(Difficulty.easy.label, 'やさしい');
    expect(Difficulty.normal.label, 'ふつう');
    expect(Difficulty.hard.label, 'むずかしい');
    expect(Difficulty.easy.key, 'easy');
    expect(Difficulty.normal.key, 'normal');
    expect(Difficulty.hard.key, 'hard');
  });

  test('difficultyFor uses inclusive upper bounds', () {
    const t = Thresholds(hard: 9, normal: 26);
    expect(difficultyFor(1, t), Difficulty.hard);
    expect(difficultyFor(9, t), Difficulty.hard);
    expect(difficultyFor(10, t), Difficulty.normal);
    expect(difficultyFor(26, t), Difficulty.normal);
    expect(difficultyFor(27, t), Difficulty.easy);
    expect(difficultyFor(96, t), Difficulty.easy);
  });

  test('computeThresholds picks the 33rd and 67th percentiles', () {
    // 1..9 の 9 要素。index 9~/3 = 3 -> 4、index 2*9~/3 = 6 -> 7。
    final t = computeThresholds([9, 1, 8, 2, 7, 3, 6, 4, 5]);
    expect(t.hard, 4);
    expect(t.normal, 7);
  });

  test('computeThresholds is independent of input order', () {
    final a = computeThresholds([5, 1, 3, 2, 4]);
    final b = computeThresholds([1, 2, 3, 4, 5]);
    expect(a.hard, b.hard);
    expect(a.normal, b.normal);
  });
}
