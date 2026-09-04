import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// 行ごとの値を読み出す(アサーションを読みやすくするため)。
List<List<int>> rowsOf(BonusGrid grid) => [
      for (var r = 0; r < kBonusSize; r++)
        [for (var c = 0; c < kBonusSize; c++) grid.valueAt(r, c)],
    ];

void main() {
  group('不正な手', () {
    test('単独のマスをタップすると null で盤面は変化しない', () {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final before = rowsOf(grid);
      expect(grid.tap(12, Random(0)), isNull);
      expect(rowsOf(grid), before);
    });
  });

  group('スコア', () {
    test('2 を 5 個まとめると 10 点(仕様 §2.3)', () {
      final grid = gridOf([
        [1, 3, 1, 3, 1],
        [2, 2, 2, 3, 1],
        [3, 2, 2, 1, 3],
        [1, 3, 1, 3, 1],
        [3, 1, 3, 1, 3],
      ]);
      final merge = grid.tap(5, Random(0))!;
      expect(merge.mergedValue, 2);
      expect(merge.mergedCount, 5);
      expect(merge.gained, 10);
    });

    test('9 を 2 個まとめると 18 点', () {
      final grid = gridOf([
        [9, 9, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.mergedValue, 9);
      expect(merge.mergedCount, 2);
      expect(merge.gained, 18);
    });

    test('9 を 4 個まとめると 36 点', () {
      final grid = gridOf([
        [9, 9, 1, 2, 1],
        [9, 9, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.mergedCount, 4);
      expect(merge.gained, 36);
    });
  });

  group('マージの結果', () {
    test('タップしたマスが n+1 になる', () {
      final grid = gridOf([
        [1, 2, 3, 4, 5],
        [6, 4, 4, 7, 8],
        [1, 2, 3, 5, 6],
        [7, 8, 1, 2, 3],
        [4, 5, 6, 7, 8],
      ]);
      final merge = grid.tap(6, Random(0))!;
      // (1,1) をタップしたので、そこが 5 になる。重力で下に落ちる余地は
      // ないので位置はそのまま。
      expect(merge.grid.valueAt(1, 1), 5);
    });

    test('合成後のマスも、その下に空きができれば落ちる', () {
      // 同じ列の (2,0) と (3,0) が 6。下側の (3,0) が消えるよう
      // 上側の (2,0) をタップすると、合成結果の 7 は 1 段落ちる。
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [6, 2, 1, 2, 1],
        [6, 1, 2, 1, 2],
        [3, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(10, Random(0))!;
      expect(merge.grid.valueAt(3, 0), 7, reason: '合成結果が 1 段落ちていない');
      expect(merge.grid.valueAt(4, 0), 3, reason: '消えていないマスが動いた');
    });

    test('列内の順序が保たれる', () {
      // 列 0 は上から 1,2,3,5,5。下端の (4,0) をタップすると、そこが 6 に
      // なり (3,0) が空く。上の 1,2,3 は空いた 1 マスぶんだけ落ちるが、
      // 相対順序は変わらない。
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [3, 2, 1, 2, 1],
        [5, 1, 2, 1, 2],
        [5, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(20, Random(0))!;
      expect(merge.grid.valueAt(1, 0), 1);
      expect(merge.grid.valueAt(2, 0), 2);
      expect(merge.grid.valueAt(3, 0), 3);
      // (4,0) は 6(合成結果、タップしたマスがそのまま最下段に残る)。
      // (0,0) は新しく湧いた値なのでここでは検査しない。
      expect(merge.grid.valueAt(4, 0), 6);
    });

    test('空きマスが残らない', () {
      final grid = gridOf([
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 2, 3],
      ]);
      final merge = grid.tap(0, Random(7))!;
      expect(merge.grid.cells, isNot(contains(kBonusEmpty)));
    });

    test('補充される値が範囲内に収まる', () {
      final grid = gridOf([
        [7, 7, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(3))!;
      // 補充直前の盤面の最大は 8(合成結果)なので、湧く値は 1..7。
      for (final v in merge.grid.cells) {
        expect(v, greaterThanOrEqualTo(1));
        expect(v, lessThanOrEqualTo(8));
      }
    });
  });

  group('クリア', () {
    test('9 を 2 個まとめると 10 ができてクリアになる', () {
      final grid = gridOf([
        [9, 9, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.cleared, isTrue);
      expect(merge.grid.valueAt(0, 0), kBonusTarget);
    });

    test('クリア時は重力も補充も走らない(仕様 §2.5)', () {
      // クリア時に重力が走ると、作った 10 が動いたり空きが埋まったりして
      // 「10 が見えている盤面」で結果画面に進めない。
      final grid = gridOf([
        [9, 9, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.grid.valueAt(0, 0), kBonusTarget, reason: '10 が動いた');
      expect(merge.grid.valueAt(0, 1), kBonusEmpty,
          reason: '消えたマスが補充されている');
    });

    test('9 未満のマージではクリアにならない', () {
      final grid = gridOf([
        [8, 8, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.cleared, isFalse);
    });
  });
}
