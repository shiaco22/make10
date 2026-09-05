import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// この手を打つと補充後に詰む盤面を、乱数の種を固定して探す。
///
/// 詰みは 8 タップに 1 回起きるので、素朴に回せばすぐ見つかる。
/// 見つからなければテスト側の前提が壊れているので、はっきり失敗させる。
({BonusGrid grid, int index, int seed}) findStuckingMove() {
  for (var seed = 0; seed < 400; seed++) {
    final random = Random(seed);
    var grid = BonusGrid.deal(Random(seed));
    for (var move = 0; move < 200; move++) {
      final tappable = [
        for (var j = 0; j < kBonusCells; j++)
          if (grid.canTap(j)) j,
      ];
      if (tappable.isEmpty) break;
      final index = tappable.first;
      // 同じ乱数列で「修復しない」を試し、詰むならその局面を返す。
      final probe = grid.tap(index, Random(seed * 7919 + move),
          repairIfStuck: false);
      if (probe != null && probe.isStuck) {
        return (grid: grid, index: index, seed: seed * 7919 + move);
      }
      final merge = grid.tap(index, random);
      if (merge == null || merge.cleared) break;
      grid = merge.grid;
    }
  }
  fail('補充後に詰む局面が 400 シード試しても見つからなかった');
}

void main() {
  group('repairIfStuck: false', () {
    test('詰んだ盤面をそのまま返し、isStuck が true になる', () {
      final found = findStuckingMove();
      final merge =
          found.grid.tap(found.index, Random(found.seed), repairIfStuck: false)!;
      expect(merge.isStuck, isTrue);
      expect(merge.grid.hasLegalMove, isFalse);
      expect(merge.repairedCells, 0, reason: '修復していないのに数えている');
    });

    test('同じ手を repairIfStuck: true で打つと修復される', () {
      final found = findStuckingMove();
      final merge =
          found.grid.tap(found.index, Random(found.seed), repairIfStuck: true)!;
      expect(merge.isStuck, isFalse);
      expect(merge.grid.hasLegalMove, isTrue);
      expect(merge.repairedCells, greaterThan(0));
    });

    test('詰んでいなければ isStuck は false', () {
      final grid = gridOf([
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 2, 3],
      ]);
      final merge = grid.tap(0, Random(7), repairIfStuck: false)!;
      expect(merge.isStuck, isFalse);
    });

    test('スコアと消えたマスの記録は修復の有無に影響されない', () {
      final found = findStuckingMove();
      final a = found.grid
          .tap(found.index, Random(found.seed), repairIfStuck: false)!;
      final b = found.grid
          .tap(found.index, Random(found.seed), repairIfStuck: true)!;
      expect(a.gained, b.gained);
      expect(a.mergedValue, b.mergedValue);
      expect(a.mergedCount, b.mergedCount);
      expect(a.removedCells, b.removedCells);
    });
  });

  group('既定の挙動', () {
    test('引数を省略すると今までどおり修復する', () {
      final found = findStuckingMove();
      final merge = found.grid.tap(found.index, Random(found.seed))!;
      expect(merge.grid.hasLegalMove, isTrue);
      expect(merge.isStuck, isFalse);
    });
  });

  test('入れ替えの上限は 10 回', () {
    expect(kBonusRepairLimit, 10);
  });
}
