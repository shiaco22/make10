# ボーナスゲーム 敗北条件とエフェクト 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ボーナスゲームの入れ替え（詰み修復）を 1 ゲーム 10 回までにし、使い切った状態で詰んだらゲームオーバーにする。あわせてマスの消滅と落下にアニメーションを付ける。

**Architecture:** 上限のカウントは盤面ではなくセッションが持つ。`BonusGrid.tap` には「修復してよいか」を引数で渡し、断られた結果詰んだかを `BonusMerge.isStuck` で返す。アニメーションに必要な「何がどこへ動いたか」は、重力計算の時点で分かっている情報を `BonusMerge` がそのまま返す（前後の盤面の差分から推測しない）。論理状態はアニメーションを待たない。

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2。**新しい依存パッケージは追加しない**（アニメーションは Flutter 標準の `AnimationController` と `Tween` で組む）。

**仕様書:** [docs/superpowers/specs/2026-09-05-bonus-gameover-and-effects-design.md](../specs/2026-09-05-bonus-gameover-and-effects-design.md)

## Global Constraints

- **Flutter は PATH に無い。** `C:/flutter/bin/flutter.bat` と `C:/flutter/bin/dart.bat` をフルパスで呼ぶ。シェルの状態はツール呼び出し間で保持されない。
- **このリポジトリのパスからは `flutter analyze` を実行できない**（非 ASCII パスで Dart 解析サーバがクラッシュする）。`flutter build apk` / `appbundle` も AGP が拒否する。`flutter test` と `flutter build web` は動く。アナライザは ASCII のパスへコピーして走らせる。
- 作業ブランチは `feat/bonus-gameover`。`main` に直接コミットしない。
- **既存の 460 テストを 1 つも壊さない。** 各タスクの最後に全体を走らせる。
- `lib/domain/` 配下では `package:flutter/` を import しない（`test/domain/domain_purity_test.dart` が検査する）。
- `analysis_options.yaml` は `flutter_lints` + `prefer_final_locals` + `avoid_print`。ローカル変数は `final`、`print` は使わない。
- 既存の日本語 doc コメントの流儀に合わせる。**「何を」ではなく「なぜ」を書く。**
- Flutter コマンドが `Upgrading analysis_options.yaml to exclude build and platform directories.` を出して同ファイルが変更扱いになったら SDK の正常な挙動。**コミットに含めない。**

## 既存コードの読みどころ

着手前に必ず読むこと。

- `lib/domain/bonus/bonus_grid.dart` — `tap` / `repairIfStuck` / `_applyGravity` / `BonusMerge` / `BonusRepair`
- `lib/game/bonus_session.dart` — `_disposed` ガードと `_finish` の非同期保存
- `lib/data/bonus_repository.dart` — `_writeQueue` による書き込みの直列化と `_decodeGrid`
- `lib/ui/bonus_game_screen.dart` / `lib/ui/bonus_result_screen.dart` / `lib/ui/widgets/bonus_grid_view.dart`

---

### Task 1: 何がどこへ動いたかを盤面が返す

**Files:**
- Modify: `lib/domain/bonus/bonus_grid.dart`（`_applyGravity` の返り値、`BonusMerge` のフィールド、`tap` の組み立て）
- Test: `test/domain/bonus/bonus_motion_test.dart`

**Interfaces:**
- Consumes: 既存の `BonusGrid` / `BonusMerge`
- Produces: `BonusMerge` に `Set<int> removedCells`、`Map<int,int> fallenCells`、`Set<int> spawnedCells`、`int mergedInto` を追加

**なぜ差分推測ではだめか:** 同じ値のマスが複数あると、前後の盤面を突き合わせても「どのマスがどこへ動いたか」の対応が一意に決まらない。落下アニメーションがそこで飛ぶ。重力の計算時点でこの情報は確定しているので、そのまま返す。

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus/bonus_motion_test.dart`:

```dart
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
      // どちらかで必ず説明できる（合成先は落下の行き先か元の位置）。
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_motion_test.dart`
Expected: FAIL — `The getter 'removedCells' isn't defined for the class 'BonusMerge'`

- [ ] **Step 3: `_applyGravity` が動きを返すようにする**

`lib/domain/bonus/bonus_grid.dart` の `_applyGravity` を置き換える。

```dart
/// 列ごとに重力を適用する。空でないマスが順序を保って下端へ落ち、
/// 空きは上端に集まる。[cells] を直接書き換える。
///
/// 動いたマスの「元の添字 → 新しい添字」を返す。動かなかったマスは
/// 含まない。アニメーションがこの対応を必要とするが、**前後の盤面の
/// 差分からは復元できない** — 同じ値のマスが複数あると対応が一意に
/// 決まらないため。ここでは確定しているので、そのまま返す。
Map<int, int> _applyGravity(List<int> cells) {
  final moved = <int, int>{};
  for (var col = 0; col < kBonusSize; col++) {
    var write = kBonusSize - 1;
    for (var row = kBonusSize - 1; row >= 0; row--) {
      final from = row * kBonusSize + col;
      final value = cells[from];
      if (value != kBonusEmpty) {
        final to = write * kBonusSize + col;
        cells[to] = value;
        if (to != from) moved[from] = to;
        write--;
      }
    }
    for (var row = write; row >= 0; row--) {
      cells[row * kBonusSize + col] = kBonusEmpty;
    }
  }
  return moved;
}
```

`to >= from` が常に成り立つ（`write` は `kBonusSize - 1` から始まり非空マス
1 つにつき 1 だけ減り、`row` は毎回 1 減るので `write >= row`）。まだ読んで
いないマスは添字が `from` より小さいので、`to` への書き込みがそれらを壊す
ことはない。

- [ ] **Step 4: `BonusMerge` にフィールドを足す**

`BonusMerge` のフィールドとコンストラクタに追加する。

```dart
  /// この手で消えたマス。手を打つ**前**の座標系。
  ///
  /// タップしたマス自身は含まない（そのマスは消えずに `n+1` になる）。
  final Set<int> removedCells;

  /// 重力で動いたマス。手を打つ前の添字 → 打った後の添字。
  /// 動かなかったマスは含まない。
  final Map<int, int> fallenCells;

  /// 補充で新しく湧いたマス。手を打った**後**の座標系。
  ///
  /// 詰み修復で書き換わったマスもここに含める。プレイヤーから見れば
  /// 「新しい数字が現れた」ことに変わりはなく、アニメーションの扱いも
  /// 同じでよい。
  final Set<int> spawnedCells;

  /// `n+1` になったマスの、手を打った**後**の位置。
  final int mergedInto;
```

コンストラクタの引数に加える（すべて必須）。

```dart
  const BonusMerge({
    required this.grid,
    required this.gained,
    required this.mergedValue,
    required this.mergedCount,
    required this.cleared,
    required this.removedCells,
    required this.fallenCells,
    required this.spawnedCells,
    required this.mergedInto,
    this.repairedCells = 0,
    this.usedFullShuffle = false,
  });
```

- [ ] **Step 5: `tap` で組み立てる**

`tap` の本体を次に置き換える（`repairIfStuck` の引数は Task 2 で足すので、
ここではまだ現状のまま）。

```dart
  BonusMerge? tap(int index, Random random) {
    final component = componentAt(index);
    if (component.length < 2) return null;

    final value = cells[index];
    final count = component.length;
    final removed = {
      for (final i in component)
        if (i != index) i,
    };

    final next = List<int>.of(cells);
    for (final i in component) {
      next[i] = kBonusEmpty;
    }
    next[index] = value + 1;

    if (value + 1 >= kBonusTarget) {
      // クリア時は重力も補充も走らせない。作った 10 が見えている盤面のまま
      // 結果画面に進むため(仕様 §2.5)。空きマスが残るが、この盤面から
      // 次の手を打つことはない。
      return BonusMerge(
        grid: BonusGrid._(next),
        gained: value * count,
        mergedValue: value,
        mergedCount: count,
        cleared: true,
        removedCells: removed,
        fallenCells: const {},
        spawnedCells: const {},
        mergedInto: index,
      );
    }

    final fallen = _applyGravity(next);
    // 補充に使う最大値は「重力の直後・補充の前」に 1 度だけ決め、補充中は
    // 更新しない(仕様 §2.4)。1 手のあいだ補充の分布が揺れないようにする。
    final boardMax = next.reduce((a, b) => a > b ? a : b);
    final spawned = <int>{};
    for (var i = 0; i < kBonusCells; i++) {
      if (next[i] == kBonusEmpty) {
        next[i] = spawnValue(boardMax, random);
        spawned.add(i);
      }
    }

    // 修復で書き換わったマスも「新しい数字が現れた」ものとして扱う。
    // どのマスが変わったかは BonusRepair が持っていないので、修復の
    // 前後をここで突き合わせる。
    final beforeRepair = List<int>.of(next);
    final repair = BonusGrid._(next).repairIfStuck(random);
    for (var i = 0; i < kBonusCells; i++) {
      if (repair.grid.cells[i] != beforeRepair[i]) spawned.add(i);
    }

    return BonusMerge(
      grid: repair.grid,
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
      removedCells: removed,
      fallenCells: fallen,
      spawnedCells: spawned,
      mergedInto: fallen[index] ?? index,
      repairedCells: repair.changedCells,
      usedFullShuffle: repair.usedFullShuffle,
    );
  }
```

- [ ] **Step 6: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_motion_test.dart`
Expected: PASS

- [ ] **Step 7: 差分推測では通らないことを確認する**

「同じ値のマスが複数あっても対応が一意に決まる」テストが本当に効いている
ことを見る。`_applyGravity` の `if (to != from) moved[from] = to;` を
一時的に `if (to != from) moved[from] = from + kBonusSize;`（「必ず 1 段だけ
落ちる」という誤った仮定）に変える。

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_motion_test.dart`
Expected: **FAIL** — 「合成後のマスも、下に空きができれば落ちる」で
`fallenCells[10]` が 15 ではなく 15（この例では偶然一致する）になるか、
「補充と落下と合成先で盤面が過不足なく説明できる」が落ちる。

**どちらのテストも落ちなかった場合は、テストが弱いということなので報告する
こと。** 確認したら元に戻し、再実行して PASS に戻す。

- [ ] **Step 8: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。既存 460 が 1 つも壊れていないこと。

- [ ] **Step 9: コミット**

```bash
git add lib/domain/bonus/bonus_grid.dart test/domain/bonus/bonus_motion_test.dart
git commit -m "feat(bonus): report which cells vanished, fell and spawned on each move"
```

---

### Task 2: 修復を断れるようにする

**Files:**
- Modify: `lib/domain/bonus/bonus_grid.dart`（`tap` の名前付き引数、`BonusMerge.isStuck`）
- Test: `test/domain/bonus/bonus_stuck_test.dart`

**Interfaces:**
- Consumes: Task 1 の `BonusMerge`
- Produces:
  - `BonusMerge? tap(int index, Random random, {bool repairIfStuck = true})`
  - `BonusMerge` に `bool isStuck`
  - `const int kBonusRepairLimit = 10;`

**既定を `true` にする理由:** 「`tap` は詰んだ盤面を返さない」という既存の
不変条件テスト（`test/domain/bonus/bonus_repair_test.dart` の 300 手回すもの）
をそのまま生かすため。呼び出し側が明示的に断ったときだけ挙動が変わる。

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus/bonus_stuck_test.dart`:

```dart
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_stuck_test.dart`
Expected: FAIL — `repairIfStuck` という名前付き引数が無い

- [ ] **Step 3: 実装する**

`lib/domain/bonus/bonus_grid.dart` の定数の並びに追加する。

```dart
/// 1 ゲームで盤面を入れ替え（詰み修復）できる回数の上限。
///
/// 上限を使い切った状態で詰んだらゲームオーバー（仕様 §2）。値を 10 に
/// したのは実測から: 10 到達率が 31.0% になり、1 日 1 回のゲームでは
/// 「3 日に 1 回くらい 10 を見られる」水準になる。5 だと 5.5%（18 日に
/// 1 回）で遠すぎ、15 だと 73.2% でほぼ負けなくなる（仕様 §2.2）。
///
/// カウントするのはセッション側（[BonusSession]）。盤面はそのゲームで
/// 何回修復したかを知らなくてよい。
const int kBonusRepairLimit = 10;
```

`BonusMerge` にフィールドを追加する。

```dart
  /// 修復を断った結果、合法手が無い盤面のまま返ってきたか。
  ///
  /// `tap(..., repairIfStuck: false)` を渡したときにだけ true になりうる。
  /// セッションはこれを見てゲームオーバーを確定する（仕様 §3.1）。
  final bool isStuck;
```

コンストラクタに `this.isStuck = false,` を加える。

`tap` のシグネチャと修復部分を変える。

```dart
  /// [repairIfStuck] を false にすると、補充後に詰んでいても修復せず、
  /// [BonusMerge.isStuck] を true にして返す。入れ替えの回数を使い切った
  /// セッションだけがこれを渡す（仕様 §2.4）。既定を true にしてあるのは、
  /// 「tap は詰んだ盤面を返さない」という既存の不変条件をそのまま
  /// 生かすため。
  BonusMerge? tap(int index, Random random, {bool repairIfStuck = true}) {
```

修復のブロックを次に置き換える。

```dart
    // 修復で書き換わったマスも「新しい数字が現れた」ものとして扱う。
    // どのマスが変わったかは BonusRepair が持っていないので、修復の
    // 前後をここで突き合わせる。
    var resulting = BonusGrid._(next);
    var repairedCells = 0;
    var usedFullShuffle = false;
    var isStuck = false;
    if (repairIfStuck) {
      final beforeRepair = List<int>.of(next);
      final repair = resulting.repairIfStuck(random);
      resulting = repair.grid;
      repairedCells = repair.changedCells;
      usedFullShuffle = repair.usedFullShuffle;
      for (var i = 0; i < kBonusCells; i++) {
        if (resulting.cells[i] != beforeRepair[i]) spawned.add(i);
      }
    } else {
      isStuck = !resulting.hasLegalMove;
    }

    return BonusMerge(
      grid: resulting,
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
      removedCells: removed,
      fallenCells: fallen,
      spawnedCells: spawned,
      mergedInto: fallen[index] ?? index,
      repairedCells: repairedCells,
      usedFullShuffle: usedFullShuffle,
      isStuck: isStuck,
    );
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_stuck_test.dart`
Expected: PASS

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**特に `test/domain/bonus/bonus_repair_test.dart` の
300 手回す不変条件テストが無変更で通ること**（既定を true にした狙い）。

- [ ] **Step 6: コミット**

```bash
git add lib/domain/bonus/bonus_grid.dart test/domain/bonus/bonus_stuck_test.dart
git commit -m "feat(bonus): let the caller decline the deadlock repair"
```

---

### Task 3: セッションの上限とゲームオーバー

**Files:**
- Modify: `lib/game/bonus_session.dart`
- Test: `test/game/bonus_gameover_test.dart`

**Interfaces:**
- Consumes: Task 2 の `tap(..., repairIfStuck:)` / `BonusMerge.isStuck` / `kBonusRepairLimit`
- Produces:
  - `enum BonusOutcome { cleared, gameOver, gaveUp }`
  - `BonusSession` に `int repairsUsed`、`int repairsLeft`、`BonusOutcome? outcome`、`bool isGameOver`
  - コンストラクタに `int repairsUsed = 0`

- [ ] **Step 1: 失敗するテストを書く**

`test/game/bonus_gameover_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/game/bonus_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// (0,0)(0,1) が 9 で、1 手でクリアできる盤面。
BonusGrid nearlyClearedGrid() => gridOf([
      [9, 9, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
    ]);

Future<BonusRepository> loadedRepo() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

Future<void> settle(BonusSession s, {int maxTurns = 50}) async {
  for (var i = 0; i < maxTurns && s.isSavingResult; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  if (s.isSavingResult) fail('isSavingResult が true のままだった');
}

/// 打てる手を順に打ち、[stopWhen] が真になったら止める。
int playUntil(BonusSession s, bool Function() stopWhen, {int maxMoves = 400}) {
  var moves = 0;
  while (moves < maxMoves && !s.isOver && !stopWhen()) {
    final tappable = [
      for (var j = 0; j < kBonusCells; j++)
        if (s.grid.canTap(j)) j,
    ];
    if (tappable.isEmpty) break;
    s.tap(tappable.first);
    moves++;
  }
  return moves;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('入れ替えの残り', () {
    test('最初は上限いっぱい', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(1)),
        score: 0,
        random: Random(1),
      );
      addTearDown(s.dispose);
      expect(s.repairsUsed, 0);
      expect(s.repairsLeft, kBonusRepairLimit);
    });

    test('修復が起きるたびに減る', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(3)),
        score: 0,
        random: Random(3),
      );
      addTearDown(s.dispose);
      playUntil(s, () => s.repairsUsed >= 3);
      expect(s.repairsUsed, greaterThanOrEqualTo(1),
          reason: '400 手打っても修復が一度も起きなかった');
      expect(s.repairsLeft, kBonusRepairLimit - s.repairsUsed);
    });

    test('残りは 0 を下回らない', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(9)),
        score: 0,
        random: Random(9),
      );
      addTearDown(s.dispose);
      playUntil(s, () => s.isOver);
      expect(s.repairsLeft, greaterThanOrEqualTo(0));
    });
  });

  group('ゲームオーバー', () {
    test('使い切ったあと詰むとゲームオーバーになる', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(9)),
        score: 0,
        random: Random(9),
      );
      addTearDown(s.dispose);
      playUntil(s, () => s.isOver);
      await settle(s);
      // seed 9 は 10 に届かずゲームオーバーになる想定。届いた場合は
      // クリアで終わっているはずで、どちらにせよ isOver は真。
      expect(s.isOver, isTrue);
      if (s.isGameOver) {
        expect(s.outcome, BonusOutcome.gameOver);
        expect(s.repairsLeft, 0);
        expect(s.grid.hasLegalMove, isFalse,
            reason: 'ゲームオーバーなのに打てる手が残っている');
      }
    });

    test('ゲームオーバーを起こした手のスコアは加算される', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(9)),
        score: 0,
        random: Random(9),
      );
      addTearDown(s.dispose);
      var lastScore = 0;
      while (!s.isOver) {
        final tappable = [
          for (var j = 0; j < kBonusCells; j++)
            if (s.grid.canTap(j)) j,
        ];
        if (tappable.isEmpty) break;
        lastScore = s.score;
        s.tap(tappable.first);
      }
      await settle(s);
      expect(s.score, greaterThan(lastScore),
          reason: '最後の手の得点が捨てられている');
    });

    test('ゲームオーバー後のタップは無視される', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(9)),
        score: 0,
        random: Random(9),
      );
      addTearDown(s.dispose);
      playUntil(s, () => s.isOver);
      await settle(s);
      final frozen = s.score;
      final cells = s.grid.cells.toList();
      for (var i = 0; i < kBonusCells; i++) {
        s.tap(i);
      }
      expect(s.score, frozen);
      expect(s.grid.cells, cells);
    });

    test('ゲームオーバーでもベストスコアが保存される', () async {
      final repo = await loadedRepo();
      await repo.earn('2026-09-05');
      await repo.startGame('2026-09-05', BonusGrid.deal(Random(9)));
      final s = BonusSession(
        repository: repo,
        grid: BonusGrid.deal(Random(9)),
        score: 0,
        random: Random(9),
      );
      addTearDown(s.dispose);
      playUntil(s, () => s.isOver);
      await settle(s);
      expect(repo.bestScore, s.score);
      expect(repo.hasInProgress, isFalse);
    });
  });

  group('outcome', () {
    test('クリアは cleared', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: nearlyClearedGrid(),
        score: 0,
        random: Random(0),
      );
      addTearDown(s.dispose);
      s.tap(0);
      await settle(s);
      expect(s.outcome, BonusOutcome.cleared);
      expect(s.isCleared, isTrue);
      expect(s.isGameOver, isFalse);
    });

    test('やめたら gaveUp', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(2)),
        score: 0,
        random: Random(2),
      );
      addTearDown(s.dispose);
      s.giveUp();
      await settle(s);
      expect(s.outcome, BonusOutcome.gaveUp);
      expect(s.isCleared, isFalse);
      expect(s.isGameOver, isFalse);
    });

    test('終わっていなければ null', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(4)),
        score: 0,
        random: Random(4),
      );
      addTearDown(s.dispose);
      expect(s.outcome, isNull);
      expect(s.isOver, isFalse);
    });
  });

  group('再開', () {
    test('使用済みの回数を引き継いで始められる', () async {
      final s = BonusSession(
        repository: await loadedRepo(),
        grid: BonusGrid.deal(Random(6)),
        score: 340,
        repairsUsed: 7,
        random: Random(6),
      );
      addTearDown(s.dispose);
      expect(s.repairsUsed, 7);
      expect(s.repairsLeft, kBonusRepairLimit - 7);
      expect(s.score, 340);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/game/bonus_gameover_test.dart`
Expected: FAIL — `BonusOutcome` が未定義

- [ ] **Step 3: 実装する**

`lib/game/bonus_session.dart` の import の下に追加する。

```dart
/// ボーナスゲーム 1 回の終わり方。
///
/// bool 2 つ（クリアしたか・やめたか）では 3 状態を表せなくなったので
/// 列挙にした。結果画面の見出しはこれで分岐する（仕様 §3.2）。
enum BonusOutcome {
  /// 10 を作った。
  cleared,

  /// 入れ替えを使い切った状態で詰んだ。
  gameOver,

  /// プレイヤーが自分でやめた。
  gaveUp,
}
```

`BonusSession` のフィールドを変える。`_cleared` と `_gaveUp` を消して
`_outcome` にする。

```dart
  BonusOutcome? _outcome;
  int _repairsUsed;
```

コンストラクタに引数を足す。

```dart
  /// [repairsUsed] は再開時に、保存されていた使用済みの回数を渡す。
  /// 渡さないと中断・再開のたびに入れ替えが上限まで戻り、上限が
  /// 事実上無くなる（仕様 §3.4）。
  BonusSession({
    required this.repository,
    required BonusGrid grid,
    required int score,
    int repairsUsed = 0,
    Random? random,
  })  : _grid = grid, // ignore: prefer_initializing_formals
        _score = score, // ignore: prefer_initializing_formals
        _repairsUsed = repairsUsed.clamp(0, kBonusRepairLimit),
        _random = random ?? Random();
```

getter を差し替える。

```dart
  /// 終わっていなければ null。
  BonusOutcome? get outcome => _outcome;

  bool get isOver => _outcome != null;
  bool get isCleared => _outcome == BonusOutcome.cleared;
  bool get isGameOver => _outcome == BonusOutcome.gameOver;

  /// このゲームで盤面を入れ替えた回数。
  int get repairsUsed => _repairsUsed;

  /// 残りの入れ替え回数。0 になると、次に詰んだ時点でゲームオーバー。
  int get repairsLeft => kBonusRepairLimit - _repairsUsed;
```

`tap` を差し替える。

```dart
  void tap(int index) {
    if (_disposed || isOver) return;
    // 残りが無いときだけ修復を断る。断った結果詰んでいたら、その手を
    // 最後にゲームオーバー（仕様 §3.1）。打った手そのものは合法なので
    // 得点は加算する。
    final merge = _grid.tap(index, _random, repairIfStuck: repairsLeft > 0);
    // 不正な手では盤面が変わらないので、再描画も促さない。
    if (merge == null) return;

    _grid = merge.grid;
    _score += merge.gained;
    _lastRepairedCells = merge.repairedCells;
    if (merge.repairedCells > 0) _repairsUsed++;

    if (merge.cleared) {
      _outcome = BonusOutcome.cleared;
      _finish();
    } else if (merge.isStuck) {
      _outcome = BonusOutcome.gameOver;
      _finish();
    } else {
      // 1 手ごとに保存する。所要 5 分前後のゲームで、電話や
      // バックグラウンド化による中断は普通に起きる(仕様 §4.3)。
      repository.saveProgress(_grid, _score, _repairsUsed).ignore();
    }
    notifyListeners();
  }
```

`giveUp` の `_gaveUp = true;` を `_outcome = BonusOutcome.gaveUp;` に変える。

import に `kBonusRepairLimit` が入っている `bonus_grid.dart` は既にあるので
追加不要。

- [ ] **Step 4: `saveProgress` の呼び出しが合うようにする**

Task 4 で `BonusRepository.saveProgress` に第 3 引数を足すが、このタスクの
時点ではまだ 2 引数なのでコンパイルが通らない。**Task 3 と Task 4 は
まとめて 1 つのコミットにせず、Task 4 を先に片付けてもよい。** 実装者は
どちらの順でもよいが、`flutter test` が通る状態でだけコミットすること。

推奨: このタスクでは `repository.saveProgress(_grid, _score).ignore();` の
ままにしておき、Task 4 で第 3 引数を足すときに同時に書き換える。その場合
このタスクの時点では `_repairsUsed` は保存されず、Task 4 のテストで初めて
保存が検査される。

- [ ] **Step 5: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/game/bonus_gameover_test.dart`
Expected: PASS

`seed 9 は 10 に届かずゲームオーバーになる想定` としたテストが、実際には
クリアで終わる場合もある。テストは `if (s.isGameOver)` で分岐してあるので
それ自体は通るが、**ゲームオーバーの経路が一度も通らないと検査が空回りする**。
`playUntil` の後に `s.isGameOver` が真になる seed を探し、そちらへ差し替える
こと。見つからなければ報告する。

- [ ] **Step 6: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。既存の `test/game/bonus_session_test.dart` は
`isCleared` を使っているが、互換の getter を残したので無変更で通るはず。
落ちる場合は getter の名前を確認する。

- [ ] **Step 7: コミット**

```bash
git add lib/game/bonus_session.dart test/game/bonus_gameover_test.dart
git commit -m "feat(bonus): end the run when the repair budget is spent"
```

---

## 残りのタスク

Task 4 以降は [part2](2026-09-05-bonus-gameover-and-effects-part2.md) に続く。

- Task 4: `repairsUsed` の永続化（中断・再開の抜け道を塞ぐ）
- Task 5: 残り回数の表示とゲームオーバーの重ね表示、結果画面の 3 状態
- Task 6: 消滅と落下のアニメーション
- Task 7: 上限を入れた実測を Dart の実エンジンで取り直し、仕様書を更新
