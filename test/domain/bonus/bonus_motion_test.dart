import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

void main() {
  group('removedCells', () {
    test('消えたマスを、手を打つ前の座標で返す', () {
      // (1,0)(1,1)(1,2)(2,1)(2,2) の 2 が 5 マス連結する。
      final grid = gridOf([
        [1, 3, 1, 3, 1],
        [2, 2, 2, 3, 1],
        [3, 2, 2, 1, 3],
        [1, 3, 1, 3, 1],
        [3, 1, 3, 1, 3],
      ]);
      final merge = grid.tap(5, Random(0))!;
      // 連結成分は {5,6,7,11,12}。タップした 5 は n+1 になって残るので
      // 消えたのは残り 4 マス。
      expect(merge.removedCells, {6, 7, 11, 12});
    });

    test('タップしたマス自身は消えたことにしない', () {
      final grid = gridOf([
        [4, 4, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.removedCells, {1});
      expect(merge.removedCells, isNot(contains(0)));
    });
  });

  group('fallenCells', () {
    test('同じ値のマスが複数あっても対応が一意に決まる', () {
      // 列 0 は上から 7,7,7,5,5。下端の 5 二つをまとめると 6 になり、
      // 上の 7 が 3 つとも 1 段ずつ落ちる。7 は互いに見分けが付かないので、
      // 前後の盤面を差分しただけでは対応を復元できない。
      final grid = gridOf([
        [7, 2, 1, 2, 1],
        [7, 1, 2, 1, 2],
        [7, 2, 1, 2, 1],
        [5, 1, 2, 1, 2],
        [5, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(20, Random(0))!;
      // (4,0)=20 をタップ。(3,0)=15 が消え、合成結果の 6 は 20 に残る
      // (下に空きが無いので動かない)。上の 7 三つが 1 段ずつ落ちる:
      // 0→5, 5→10, 10→15。
      expect(merge.fallenCells[0], 5);
      expect(merge.fallenCells[5], 10);
      expect(merge.fallenCells[10], 15);
      expect(merge.fallenCells.containsKey(20), isFalse,
          reason: '動いていないマスを fallenCells に入れてはいけない');
    });

    test('合成後のマスも、下に空きができれば落ちる', () {
      // 列 0 の (2,0)=10 と (3,0)=15 が 6。上側の 10 をタップすると
      // 15 が空き、合成結果の 7 は 15 へ落ちる。
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [6, 2, 1, 2, 1],
        [6, 1, 2, 1, 2],
        [3, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(10, Random(0))!;
      expect(merge.fallenCells[10], 15);
      expect(merge.mergedInto, 15);
      expect(merge.grid.cells[15], 7);
    });

    test('2 段落下する例で、1 段落下という誤った仮定と結果が食い違う', () {
      // 列 0 の (2,0)(3,0)(4,0) の 8 が 3 マス連結する。タップした
      // (2,0)=10 は 9 になって残り、(3,0)=15 と (4,0)=20 の 2 マスが
      // 空く。空きが 2 段重なるので、合成結果の 9 は 1 段ではなく
      // 2 段落ちて 20 に着地する。「必ず 1 段だけ落ちる」という誤った
      // 実装だと、この場合だけは (10 → 15) と誤答して見分けが付く。
      final grid = gridOf([
        [3, 2, 1, 2, 1],
        [9, 1, 2, 1, 2],
        [8, 2, 1, 2, 1],
        [8, 1, 2, 1, 2],
        [8, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(10, Random(0))!;
      expect(merge.fallenCells[10], 20);
      expect(merge.fallenCells[5], 15);
      expect(merge.fallenCells[0], 10);
      expect(merge.mergedInto, 20);
      expect(merge.grid.cells[20], 9);
    });

    test('動かなかったマスは含まない', () {
      final grid = gridOf([
        [1, 1, 2, 3, 2],
        [3, 2, 3, 2, 3],
        [2, 3, 2, 3, 2],
        [3, 2, 3, 2, 3],
        [2, 3, 2, 3, 2],
      ]);
      final merge = grid.tap(0, Random(0))!;
      // 列 2..4 は何も消えていないので、その列のマスは 1 つも動かない。
      for (final from in merge.fallenCells.keys) {
        expect(from % kBonusSize, lessThan(2),
            reason: '何も消えていない列のマスが動いたことになっている');
      }
    });

    test('行き先が盤面の範囲に収まる', () {
      final random = Random(5);
      var grid = BonusGrid.deal(Random(5));
      for (var i = 0; i < 60; i++) {
        final tappable = [
          for (var j = 0; j < kBonusCells; j++)
            if (grid.canTap(j)) j,
        ];
        if (tappable.isEmpty) break;
        final merge = grid.tap(tappable.first, random)!;
        for (final entry in merge.fallenCells.entries) {
          expect(entry.key, inInclusiveRange(0, kBonusCells - 1));
          expect(entry.value, inInclusiveRange(0, kBonusCells - 1));
        }
        expect(merge.mergedInto, inInclusiveRange(0, kBonusCells - 1));
        if (merge.cleared) break;
        grid = merge.grid;
      }
    });
  });

  group('spawnedCells', () {
    test('補充されたマスを、手を打った後の座標で返す', () {
      final grid = gridOf([
        [1, 3, 1, 3, 1],
        [2, 2, 2, 3, 1],
        [3, 2, 2, 1, 3],
        [1, 3, 1, 3, 1],
        [3, 1, 3, 1, 3],
      ]);
      final merge = grid.tap(5, Random(0))!;
      // 5 マス連結のうち 4 マスが空き、重力で空きは上端に集まる。
      expect(merge.spawnedCells.length, greaterThanOrEqualTo(4));
      for (final i in merge.spawnedCells) {
        expect(i, inInclusiveRange(0, kBonusCells - 1));
      }
    });

    test('補充と落下と合成先で盤面が過不足なく説明できる', () {
      // 手を打った後の 25 マスは「落ちてきたマス」「補充されたマス」の
      // どちらかで必ず説明できる(合成先は落下の行き先か元の位置)。
      final random = Random(11);
      var grid = BonusGrid.deal(Random(11));
      for (var round = 0; round < 40; round++) {
        final tappable = [
          for (var j = 0; j < kBonusCells; j++)
            if (grid.canTap(j)) j,
        ];
        if (tappable.isEmpty) break;
        final merge = grid.tap(tappable.first, random)!;
        if (merge.cleared) break;

        final explained = <int>{
          ...merge.fallenCells.values,
          ...merge.spawnedCells,
          merge.mergedInto,
        };
        // 動かず消えもしなかったマスは explained に入らない。それらは
        // 手を打つ前と同じ位置に同じ値があるはず。
        for (var i = 0; i < kBonusCells; i++) {
          if (explained.contains(i)) continue;
          expect(merge.grid.cells[i], grid.cells[i],
              reason: '添字 $i は動いたとも湧いたとも報告されていないのに '
                  '値が変わっている');
        }
        grid = merge.grid;
      }
    });
  });

  group('クリア時', () {
    test('重力も補充も走らないので fallenCells と spawnedCells は空', () {
      final grid = gridOf([
        [9, 9, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(0, Random(0))!;
      expect(merge.cleared, isTrue);
      expect(merge.fallenCells, isEmpty);
      expect(merge.spawnedCells, isEmpty);
      expect(merge.removedCells, {1});
      expect(merge.mergedInto, 0);
    });
  });
}
