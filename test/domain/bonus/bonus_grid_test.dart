import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

/// 5x5 を読みやすく書くためのヘルパ。行ごとのリストを平らにする。
BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

void main() {
  group('BonusGrid.of', () {
    test('25 マスでなければ拒否する', () {
      expect(() => BonusGrid.of(List.filled(24, 1)), throwsArgumentError);
      expect(() => BonusGrid.of(List.filled(26, 1)), throwsArgumentError);
    });

    test('cells は書き換えられない', () {
      final grid = BonusGrid.of(List.filled(kBonusCells, 1));
      expect(() => grid.cells[0] = 9, throwsUnsupportedError);
    });

    test('valueAt が row-major で引ける', () {
      final grid = gridOf([
        [1, 2, 3, 4, 5],
        [6, 7, 8, 9, 1],
        [2, 3, 4, 5, 6],
        [7, 8, 9, 1, 2],
        [3, 4, 5, 6, 7],
      ]);
      expect(grid.valueAt(0, 0), 1);
      expect(grid.valueAt(0, 4), 5);
      expect(grid.valueAt(4, 0), 3);
      expect(grid.valueAt(1, 3), 9);
    });

    test('maxValue は最大値を返す', () {
      final grid = gridOf([
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 7, 1, 1],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
      ]);
      expect(grid.maxValue, 7);
    });
  });

  group('componentAt', () {
    test('単独のマスは自分だけ', () {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      expect(grid.componentAt(12), {12});
      expect(grid.canTap(12), isFalse);
    });

    test('横に 2 つ並ぶと 2 マス', () {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 3, 3, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      expect(grid.componentAt(6), {6, 7});
      expect(grid.componentAt(7), {6, 7});
      expect(grid.canTap(6), isTrue);
    });

    test('L 字に連結する', () {
      // (1,1) (1,2) (2,2) の 3 マスが 3 で連結する
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 3, 3, 1, 2],
        [1, 2, 3, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      expect(grid.componentAt(6), {6, 7, 12});
    });

    test('十字に連結する', () {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 4, 1, 2],
        [1, 4, 4, 4, 1],
        [2, 1, 4, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      expect(grid.componentAt(12), {7, 11, 12, 13, 17});
    });

    test('斜めは連結しない', () {
      final grid = gridOf([
        [5, 1, 2, 1, 2],
        [1, 5, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
      ]);
      expect(grid.componentAt(0), {0});
      expect(grid.canTap(0), isFalse);
    });

    test('盤面の端で列をまたがない', () {
      // (0,4) と (1,0) は添字が隣 (4 と 5) だが、盤面上では隣接しない。
      final grid = gridOf([
        [1, 2, 1, 2, 7],
        [7, 1, 2, 1, 2],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
      ]);
      expect(grid.componentAt(4), {4});
      expect(grid.componentAt(5), {5});
    });
  });

  group('hasLegalMove', () {
    test('市松模様は合法手なし', () {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      expect(grid.hasLegalMove, isFalse);
    });

    test('同値が 1 組でも隣接すれば合法手あり', () {
      final grid = gridOf([
        [1, 1, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      expect(grid.hasLegalMove, isTrue);
    });
  });
}
