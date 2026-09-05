import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// 同値が隣接しない 5x5(3 彩色に相当する並び)。合法手が 1 つも無い。
BonusGrid stuckGrid() => gridOf([
      [1, 2, 3, 1, 2],
      [3, 1, 2, 3, 1],
      [2, 3, 1, 2, 3],
      [1, 2, 3, 1, 2],
      [3, 1, 2, 3, 1],
    ]);

void main() {
  group('repairIfStuck', () {
    test('合法手があれば何もしない', () {
      final grid = gridOf([
        [1, 1, 3, 1, 2],
        [3, 1, 2, 3, 1],
        [2, 3, 1, 2, 3],
        [1, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
      ]);
      final repair = grid.repairIfStuck(Random(0));
      expect(repair.changedCells, 0);
      expect(repair.grid.cells, grid.cells);
      expect(repair.usedFullShuffle, isFalse);
    });

    test('詰みを検出して修復後は必ず合法手がある', () {
      expect(stuckGrid().hasLegalMove, isFalse);
      for (var seed = 0; seed < 50; seed++) {
        final repair = stuckGrid().repairIfStuck(Random(seed));
        expect(repair.grid.hasLegalMove, isTrue,
            reason: 'seed=$seed で修復後も詰んでいる');
        expect(repair.changedCells, greaterThan(0));
        // stuckGrid()(boardMax=3)では、20 万 seed の探索でも手順 2 に
        // 落ちた例が無かった(下の「手順 2 に落ちる」テストの注記を
        // 参照)。この 50 seed は手順 1 で解決するはず。
        expect(repair.usedFullShuffle, isFalse,
            reason: 'seed=$seed で手順 2(全並べ替え)に落ちた');
      }
    });

    test('手順 2(全並べ替え)まで落ちると usedFullShuffle が true になる', () {
      // stuckGrid()(値は 1..3 のみ、boardMax=3)は引き直しの選択肢が
      // {1, 2} の 2 つしか無く、手順 1 が 25 回とも失敗する経路は
      // 20 万 seed の探索でも 1 つも見つからなかった(0/200,000)。
      //
      // 手順 2 を現実的な頻度で踏ませるには選択肢を増やす必要がある。
      // 詰みを保ったまま 1 マスだけ、他のどのマスとも値が被らない
      // 高い数字(9)に差し替えると、boardMax が 9 になり引き直しの
      // 選択肢が 1..8 の 8 つに増える。この盤面・seed の組み合わせは
      // 同じ探索(20 万 seed)で見つけた実例(12/200,000 が該当し、
      // 最初に見つかったのが seed=1991)。
      final grid = gridOf([
        [9, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
        [2, 3, 1, 2, 3],
        [1, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
      ]);
      expect(grid.hasLegalMove, isFalse);

      final repair = grid.repairIfStuck(Random(1991));

      expect(repair.usedFullShuffle, isTrue);
      expect(repair.grid.hasLegalMove, isTrue);
      // 手順 2 は盤面全体の並べ替えなので、手順 1(実測 3.0 マス程度、
      // 仕様 §3.2)よりずっと多くのマスが変わる。
      expect(repair.changedCells, greaterThan(15));
    });

    test('修復で最大値のマスが動かない(仕様 §2.6)', () {
      // 全並べ替えは 25 マス中 21.2 マスを書き換え、最大値の位置を 99%
      // 壊す。プレイヤーが積み上げたものを 8 タップごとに散らさないため、
      // 低い値のマスから引き直す。
      final grid = gridOf([
        [9, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
        [2, 3, 1, 2, 3],
        [1, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
      ]);
      expect(grid.hasLegalMove, isFalse);
      for (var seed = 0; seed < 50; seed++) {
        final repair = grid.repairIfStuck(Random(seed));
        expect(repair.grid.valueAt(0, 0), 9,
            reason: 'seed=$seed で最大値のマスが書き換わった');
      }
    });

    test('書き換えるマス数が少ない', () {
      // 実測の中央的な値は 3.0 マス。上限として 10 マスを置く
      // (全並べ替えの 21.2 マスと明確に区別できる水準)。
      var total = 0;
      const seeds = 50;
      for (var seed = 0; seed < seeds; seed++) {
        total += stuckGrid().repairIfStuck(Random(seed)).changedCells;
      }
      expect(total / seeds, lessThan(10));
    });
  });

  group('BonusGrid.deal', () {
    test('25 マスすべてが 1..3 に収まる(仕様 §2.7)', () {
      for (var seed = 0; seed < 50; seed++) {
        final grid = BonusGrid.deal(Random(seed));
        expect(grid.cells.length, kBonusCells);
        for (final v in grid.cells) {
          expect(v, greaterThanOrEqualTo(1));
          expect(v, lessThanOrEqualTo(3));
        }
      }
    });

    test('全マスが同じ値にならない', () {
      // m=1 で埋めると 25 マス全部が 1 になり、最初のタップが 25 マスを
      // 一括マージするだけの退化した開幕になる(仕様 §2.7)。
      var sawMixed = false;
      for (var seed = 0; seed < 20 && !sawMixed; seed++) {
        final grid = BonusGrid.deal(Random(seed));
        if (grid.cells.toSet().length > 1) sawMixed = true;
      }
      expect(sawMixed, isTrue, reason: '初期盤面が単一の値で埋まっている');
    });

    test('必ず合法手がある', () {
      for (var seed = 0; seed < 100; seed++) {
        expect(BonusGrid.deal(Random(seed)).hasLegalMove, isTrue,
            reason: 'seed=$seed の初期盤面で 1 手も打てない');
      }
    });
  });

  group('tap の後の盤面', () {
    test('補充の後に詰んでいたら修復済みで返る', () {
      // 1 手ごとに詰み検査を通しているので、tap が返す盤面(クリアを
      // 除く)は常に合法手を持つ。
      final random = Random(11);
      var grid = BonusGrid.deal(Random(11));
      for (var i = 0; i < 300; i++) {
        final tappable = [
          for (var j = 0; j < kBonusCells; j++)
            if (grid.canTap(j)) j,
        ];
        expect(tappable, isNotEmpty, reason: '$i 手目で打てる手が無い');
        final merge = grid.tap(tappable.first, random)!;
        if (merge.cleared) return;
        grid = merge.grid;
      }
    });
  });
}
