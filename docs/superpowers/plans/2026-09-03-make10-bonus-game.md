# ボーナスゲーム 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** タイムアタックで 1 回に 5 問クリアすると解禁される、1 日 1 回だけ遊べる 5×5 の数字マージパズルを既存アプリに追加する。

**Architecture:** 盤面のルールは `lib/domain/bonus/` の純粋関数（Flutter 非依存・イミュータブル）に閉じ込め、1 日 1 回の権利判定は盤面を知らない `lib/domain/bonus_ticket.dart` に分ける。`BonusSession`（ChangeNotifier）が乱数と永続化をつなぎ、UI はそれを購読する。既存 MAKE10 のルール（`Board` / `Solver`）とはコードを共有しない。

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2、flutter_riverpod 3.4.2、shared_preferences 2.5.5。新しい依存パッケージは追加しない。

**仕様書:** [docs/superpowers/specs/2026-09-03-make10-bonus-game-design.md](../specs/2026-09-03-make10-bonus-game-design.md)

## Global Constraints

- **Flutter は PATH に無い。** `C:/flutter/bin/flutter.bat` と `C:/flutter/bin/dart.bat` をフルパスで呼ぶ。シェルの状態はツール呼び出し間で保持されない。
- **このリポジトリのパスからは `flutter analyze` を実行できない**（非 ASCII パスで Dart 解析サーバがクラッシュする）。`flutter build apk` / `appbundle` も同様に AGP が拒否する。`flutter test` と `flutter build web` は動く。
- 作業ブランチは `feat/bonus-game`。`main` に直接コミットしない。
- **既存の 319 テストを 1 つも壊さない。** 各タスクの最後に全体を走らせて数を確認する。
- `lib/domain/` 配下では `package:flutter/` を import しない（Task 6 が機械的に検査する）。
- `analysis_options.yaml` は `flutter_lints` + `prefer_final_locals` + `avoid_print`。ローカル変数は `final`、`print` は使わない。
- 既存の日本語 doc コメントの流儀に合わせる。**「何を」ではなく「なぜ」を書く。**
- 盤面の永続化で JSON 配列を復元するときは **`List<int>.from(...)`**。`cast<int>()` は遅延評価で、壊れたデータが `load()` の try/catch をすり抜ける（過去に踏んだ不具合）。
- Flutter コマンドが `Upgrading analysis_options.yaml to exclude build and platform directories.` を出して同ファイルが変更扱いになったら、それは SDK の正常な挙動。**コミットに含めない。**

---

### Task 1: 盤面の表現と連結成分

**Files:**
- Create: `lib/domain/bonus/bonus_grid.dart`
- Test: `test/domain/bonus/bonus_grid_test.dart`

**Interfaces:**
- Consumes: なし
- Produces:
  - `const int kBonusSize = 5;`
  - `const int kBonusCells = 25;`
  - `const int kBonusTarget = 10;`
  - `const int kBonusEmpty = 0;`
  - `class BonusGrid` — `BonusGrid.of(List<int> cells)`、`List<int> get cells`（unmodifiable、長さ 25）、`int valueAt(int row, int col)`、`int get maxValue`、`Set<int> componentAt(int index)`、`bool canTap(int index)`、`bool get hasLegalMove`

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus/bonus_grid_test.dart`:

```dart
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_grid_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'make10' ... bonus_grid.dart`（ファイルが存在しない）

- [ ] **Step 3: 実装を書く**

`lib/domain/bonus/bonus_grid.dart`:

```dart
/// 盤面の一辺のマス数。
const int kBonusSize = 5;

/// 盤面のマス数。
const int kBonusCells = kBonusSize * kBonusSize;

/// このボーナスゲームの目標値。
const int kBonusTarget = 10;

/// 空きマスを表す値。
///
/// 1 手の途中（マージ直後から補充までの間）にだけ現れる内部状態で、
/// プレイヤーには見えない。0 は正規の値 1..10 より小さいので、
/// [BonusGrid.maxValue] は空きを特別扱いせずに最大値を取れる。
const int kBonusEmpty = 0;

/// 添字 [i] の上下左右の添字。
///
/// 添字が隣（4 と 5 など）でも行が変われば盤面上では隣接しないため、
/// 列の端をまたがないよう row/col に戻して判定する。1 手ごとに
/// 塗り広げで何度も引くので、起動時に 1 度だけ作って使い回す。
final List<List<int>> _neighbors = List.generate(kBonusCells, (i) {
  final row = i ~/ kBonusSize;
  final col = i % kBonusSize;
  return <int>[
    if (row > 0) i - kBonusSize,
    if (row < kBonusSize - 1) i + kBonusSize,
    if (col > 0) i - 1,
    if (col < kBonusSize - 1) i + 1,
  ];
});

/// ボーナスゲームの盤面。イミュータブルで、1 手ごとに新しい盤面を返す
/// （既存 `Board` と同じ流儀）。
class BonusGrid {
  final List<int> cells;

  BonusGrid._(List<int> cells) : cells = List.unmodifiable(cells);

  /// 長さ [kBonusCells] のリストから作る。row-major（添字 = row * 5 + col）。
  factory BonusGrid.of(List<int> cells) {
    if (cells.length != kBonusCells) {
      throw ArgumentError.value(
        cells.length,
        'cells.length',
        '盤面は $kBonusCells マスでなければならない',
      );
    }
    return BonusGrid._(List<int>.of(cells));
  }

  int valueAt(int row, int col) => cells[row * kBonusSize + col];

  /// 盤面の最大値。空きマス（[kBonusEmpty]）は 0 なので結果に影響しない。
  int get maxValue => cells.reduce((a, b) => a > b ? a : b);

  /// [index] から上下左右に連結する同値マスの集合（[index] 自身を含む）。
  Set<int> componentAt(int index) {
    final value = cells[index];
    final seen = <int>{index};
    final stack = <int>[index];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      for (final j in _neighbors[i]) {
        if (cells[j] == value && seen.add(j)) {
          stack.add(j);
        }
      }
    }
    return seen;
  }

  /// [index] をタップできるか。同値の隣接が 1 つも無ければ打てない。
  bool canTap(int index) => componentAt(index).length >= 2;

  /// 盤面のどこかに合法手があるか。
  ///
  /// 連結成分を数える必要はない。同値の隣接が 1 組でもあればそこが合法手
  /// なので、隣接の走査だけで済む（詰み判定は 1 手ごとに走るため、
  /// 塗り広げを 25 回するより安い）。
  bool get hasLegalMove {
    for (var i = 0; i < kBonusCells; i++) {
      for (final j in _neighbors[i]) {
        if (cells[i] == cells[j]) return true;
      }
    }
    return false;
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_grid_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 6: コミット**

```bash
git add lib/domain/bonus/bonus_grid.dart test/domain/bonus/bonus_grid_test.dart
git commit -m "feat(bonus): add the 5x5 grid and its connected-component rule"
```

---

### Task 2: 補充される数字の抽選

**Files:**
- Create: `lib/domain/bonus/spawn_rule.dart`
- Test: `test/domain/bonus/spawn_rule_test.dart`

**Interfaces:**
- Consumes: なし（`bonus_grid.dart` にも依存しない — 盤面の最大値を `int` で受け取るだけ）
- Produces: `int spawnValue(int boardMax, Random random)`、`List<double> spawnWeights(int boardMax)`

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus/spawn_rule_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/spawn_rule.dart';

void main() {
  group('spawnValue の範囲', () {
    test('盤面の最大が 1 なら 1 しか返さない', () {
      final random = Random(0);
      for (var i = 0; i < 200; i++) {
        expect(spawnValue(1, random), 1);
      }
    });

    test('盤面の最大が 2 でも 1 しか返さない', () {
      final random = Random(0);
      for (var i = 0; i < 200; i++) {
        expect(spawnValue(2, random), 1);
      }
    });

    test('上端は max - 1 で、それを超えない', () {
      final random = Random(1);
      for (var i = 0; i < 2000; i++) {
        final v = spawnValue(6, random);
        expect(v, greaterThanOrEqualTo(1));
        expect(v, lessThanOrEqualTo(5));
      }
    });

    test('下端は常に 1 で、盤面が育っても 1 は湧き続ける', () {
      // 仕様 §2.4: サンプルゲームで最大 9 の局面でも 1 が出ていた。
      // 範囲を [m-3, m-1] にすると 1 の出現率が 0% になり観測と矛盾する。
      final random = Random(2);
      var sawOne = false;
      for (var i = 0; i < 2000 && !sawOne; i++) {
        if (spawnValue(9, random) == 1) sawOne = true;
      }
      expect(sawOne, isTrue, reason: '盤面の最大が 9 のとき 1 が一度も湧かなかった');
    });
  });

  group('spawnWeights', () {
    test('重みは 1/sqrt(v)', () {
      final weights = spawnWeights(5); // 範囲 1..4
      expect(weights.length, 4);
      expect(weights[0], closeTo(1.0, 1e-12));
      expect(weights[1], closeTo(1 / sqrt(2), 1e-12));
      expect(weights[2], closeTo(1 / sqrt(3), 1e-12));
      expect(weights[3], closeTo(1 / sqrt(4), 1e-12));
    });

    test('盤面の最大が 1 でも 2 でも長さ 1', () {
      expect(spawnWeights(1).length, 1);
      expect(spawnWeights(2).length, 1);
    });
  });

  test('盤面の最大が 9 のときの分布が仕様 §2.4 の表と一致する', () {
    // 仕様の表は 20 万回の抽選で実測したもの。ここでは 10 万回で
    // ±0.6 ポイントの許容を置く（Random を固定しているので決定的）。
    const expected = <int, double>{
      1: 22.9, 2: 16.0, 3: 13.3, 4: 11.4,
      5: 10.1, 6: 9.3, 7: 8.7, 8: 8.1,
    };
    const draws = 100000;
    final random = Random(20260903);
    final counts = <int, int>{};
    for (var i = 0; i < draws; i++) {
      final v = spawnValue(9, random);
      counts[v] = (counts[v] ?? 0) + 1;
    }
    expect(counts.keys.toList()..sort(), expected.keys.toList()..sort(),
        reason: '9 が湧いてはいけない（範囲は 1..8）');
    for (final entry in expected.entries) {
      final actual = counts[entry.key]! / draws * 100;
      expect(actual, closeTo(entry.value, 0.6),
          reason: '値 ${entry.key} の出現率が仕様の表とずれている');
    }
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/spawn_rule_test.dart`
Expected: FAIL — `spawn_rule.dart` が存在しない

- [ ] **Step 3: 実装を書く**

`lib/domain/bonus/spawn_rule.dart`:

```dart
import 'dart:math';

/// 上から補充される数字を決める（仕様 §2.4）。
///
/// 範囲は `1 .. max(1, boardMax - 1)`、値 `v` の重みは `1 / √v`。
///
/// **範囲の下端が常に 1 であることが要点。** 盤面がどれだけ育っても 1 は
/// 湧き続ける。サンプルゲームの観測（盤面の最大が 9 の局面でも 1 が
/// 出現していた）に合わせた要件であると同時に、「低い数字が湧かなくなると
/// 取り残された低いマスが二度と合成できず盤面を塞ぐ」という不具合を
/// 構造的に防いでいる。範囲を `[boardMax - 3, boardMax - 1]` にする案は、
/// 最大 9 で 1 の出現率が 0.0% になり観測と矛盾するため棄却した
/// （仕様 §10.1）。
///
/// `1 / √v` という重みは実測で選んだ。1 の出現率 22.9%（体感できる割合）と
/// 10 到達までの所要 5 分前後が両立する点である（仕様 §3.1）。

/// [boardMax] のときに抽選対象になる値ごとの重み。添字 0 が値 1 に対応する。
List<double> spawnWeights(int boardMax) {
  final hi = boardMax - 1 < 1 ? 1 : boardMax - 1;
  return List<double>.generate(hi, (i) => 1 / sqrt(i + 1));
}

/// [boardMax] のときに湧く数字を 1 つ引く。
int spawnValue(int boardMax, Random random) {
  final weights = spawnWeights(boardMax);
  if (weights.length == 1) return 1;
  var total = 0.0;
  for (final w in weights) {
    total += w;
  }
  final target = random.nextDouble() * total;
  var acc = 0.0;
  for (var i = 0; i < weights.length; i++) {
    acc += weights[i];
    if (target < acc) return i + 1;
  }
  // 浮動小数の誤差で acc が total にわずかに届かなかった場合の保険。
  // 分布に意味のある偏りを与えない（最後の 1 つに寄るだけ）。
  return weights.length;
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/spawn_rule_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 6: コミット**

```bash
git add lib/domain/bonus/spawn_rule.dart test/domain/bonus/spawn_rule_test.dart
git commit -m "feat(bonus): draw refill values with weight 1/sqrt(v) over 1..max-1"
```

---

### Task 3: マージ・スコア・重力・補充・クリア

**Files:**
- Modify: `lib/domain/bonus/bonus_grid.dart`（`BonusMerge` と `BonusGrid.tap` を追加）
- Test: `test/domain/bonus/bonus_merge_test.dart`

**Interfaces:**
- Consumes: Task 1 の `BonusGrid`、Task 2 の `spawnValue`
- Produces:
  - `class BonusMerge` — `BonusGrid grid`、`int gained`、`int mergedValue`、`int mergedCount`、`bool cleared`
  - `BonusMerge? BonusGrid.tap(int index, Random random)` — 不正な手なら `null`

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus/bonus_merge_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// 行ごとの値を読み出す（アサーションを読みやすくするため）。
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
    test('2 を 5 個まとめると 10 点（仕様 §2.3）', () {
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
      // 列 0 は上から 1,2,3,5,5。下端の 5 二つが消えて 6 になり、
      // 上の 1,2,3 はそのぶん落ちるが順序は変わらない。
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [3, 2, 1, 2, 1],
        [5, 1, 2, 1, 2],
        [5, 2, 1, 2, 1],
      ]);
      final merge = grid.tap(20, Random(0))!;
      expect(merge.grid.valueAt(2, 0), 1);
      expect(merge.grid.valueAt(3, 0), 2);
      // (4,0) は 6（合成結果）、(1,0) は新しく湧いた値。
      expect(merge.grid.valueAt(4, 0), 6);
      expect(merge.grid.valueAt(1, 0), 3);
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
      // 補充直前の盤面の最大は 8（合成結果）なので、湧く値は 1..7。
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

    test('クリア時は重力も補充も走らない（仕様 §2.5）', () {
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_merge_test.dart`
Expected: FAIL — `The method 'tap' isn't defined for the class 'BonusGrid'`

- [ ] **Step 3: 実装を書く**

`lib/domain/bonus/bonus_grid.dart` の先頭に import を追加:

```dart
import 'dart:math';

import 'spawn_rule.dart';
```

同ファイルの末尾（`BonusGrid` クラスの外）に追加:

```dart
/// 1 手の結果。
class BonusMerge {
  /// 手を適用した後の盤面。
  final BonusGrid grid;

  /// この手で得た点数（`mergedValue * mergedCount`）。
  final int gained;

  /// まとめたマスの数字。
  final int mergedValue;

  /// まとめたマスの数（タップしたマス自身を含む）。
  final int mergedCount;

  /// この手で [kBonusTarget] ができたか。
  final bool cleared;

  const BonusMerge({
    required this.grid,
    required this.gained,
    required this.mergedValue,
    required this.mergedCount,
    required this.cleared,
  });
}
```

`BonusGrid` クラスの中（`canTap` の後）に追加:

```dart
  /// [index] をタップした結果を返す。ルール上打てない手なら null
  /// （盤面は一切変化しない — 既存 `Board.apply` と同じ契約）。
  ///
  /// [random] は補充に使う。盤面自体は不変なので、乱数は呼び出しごとに
  /// 外から渡す（`PuzzleRepository` と同じ、注入して再現可能にする流儀）。
  BonusMerge? tap(int index, Random random) {
    final component = componentAt(index);
    if (component.length < 2) return null;

    final value = cells[index];
    final count = component.length;
    final next = List<int>.of(cells);
    for (final i in component) {
      next[i] = kBonusEmpty;
    }
    next[index] = value + 1;

    if (value + 1 >= kBonusTarget) {
      // クリア時は重力も補充も走らせない。作った 10 が見えている盤面のまま
      // 結果画面に進むため（仕様 §2.5）。空きマスが残るが、この盤面から
      // 次の手を打つことはない。
      return BonusMerge(
        grid: BonusGrid._(next),
        gained: value * count,
        mergedValue: value,
        mergedCount: count,
        cleared: true,
      );
    }

    _applyGravity(next);
    // 補充に使う最大値は「重力の直後・補充の前」に 1 度だけ決め、補充中は
    // 更新しない（仕様 §2.4）。1 手のあいだ補充の分布が揺れないようにする。
    final boardMax = next.reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < kBonusCells; i++) {
      if (next[i] == kBonusEmpty) {
        next[i] = spawnValue(boardMax, random);
      }
    }

    return BonusMerge(
      grid: BonusGrid._(next),
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
    );
  }
```

同ファイルの末尾（トップレベル）に追加:

```dart
/// 列ごとに重力を適用する。空でないマスが順序を保って下端へ落ち、
/// 空きは上端に集まる。[cells] を直接書き換える。
void _applyGravity(List<int> cells) {
  for (var col = 0; col < kBonusSize; col++) {
    var write = kBonusSize - 1;
    for (var row = kBonusSize - 1; row >= 0; row--) {
      final value = cells[row * kBonusSize + col];
      if (value != kBonusEmpty) {
        cells[write * kBonusSize + col] = value;
        write--;
      }
    }
    for (var row = write; row >= 0; row--) {
      cells[row * kBonusSize + col] = kBonusEmpty;
    }
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_merge_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 6: コミット**

```bash
git add lib/domain/bonus/bonus_grid.dart test/domain/bonus/bonus_merge_test.dart
git commit -m "feat(bonus): merge a component into n+1, score n*k, then fall and refill"
```

---

### Task 4: 詰みの修復と初期盤面

**Files:**
- Modify: `lib/domain/bonus/bonus_grid.dart`（`BonusRepair`、`repairIfStuck`、`BonusGrid.deal` を追加。`tap` に修復の呼び出しを足す）
- Test: `test/domain/bonus/bonus_repair_test.dart`

**Interfaces:**
- Consumes: Task 1〜3
- Produces:
  - `class BonusRepair` — `BonusGrid grid`、`int changedCells`
  - `BonusRepair BonusGrid.repairIfStuck(Random random)`
  - `factory BonusGrid.deal(Random random)`
  - `BonusMerge` に `int repairedCells` を追加

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus/bonus_repair_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// 同値が隣接しない 5x5（3 彩色に相当する並び）。合法手が 1 つも無い。
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
    });

    test('詰みを検出して修復後は必ず合法手がある', () {
      expect(stuckGrid().hasLegalMove, isFalse);
      for (var seed = 0; seed < 50; seed++) {
        final repair = stuckGrid().repairIfStuck(Random(seed));
        expect(repair.grid.hasLegalMove, isTrue,
            reason: 'seed=$seed で修復後も詰んでいる');
        expect(repair.changedCells, greaterThan(0));
      }
    });

    test('修復で最大値のマスが動かない（仕様 §2.6）', () {
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
      // （全並べ替えの 21.2 マスと明確に区別できる水準）。
      var total = 0;
      const seeds = 50;
      for (var seed = 0; seed < seeds; seed++) {
        total += stuckGrid().repairIfStuck(Random(seed)).changedCells;
      }
      expect(total / seeds, lessThan(10));
    });
  });

  group('BonusGrid.deal', () {
    test('25 マスすべてが 1..3 に収まる（仕様 §2.7）', () {
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
      // 一括マージするだけの退化した開幕になる（仕様 §2.7）。
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
      // 1 手ごとに詰み検査を通しているので、tap が返す盤面（クリアを
      // 除く）は常に合法手を持つ。
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_repair_test.dart`
Expected: FAIL — `The method 'repairIfStuck' isn't defined` / `deal` が無い

- [ ] **Step 3: 実装を書く**

`lib/domain/bonus/bonus_grid.dart` の `BonusMerge` に修復のマス数を追加する。フィールドとコンストラクタを次のように変える:

```dart
  /// この手の補充後に詰みを修復して書き換えたマス数。0 なら修復していない。
  ///
  /// 詰みは 1 ゲームに 13 回、およそ 8 タップに 1 回起きる（仕様 §3.2）。
  /// 無言で盤面を書き換えると理不尽に見えるので、UI が通知を出せるように
  /// 手の結果として返す。
  final int repairedCells;

  const BonusMerge({
    required this.grid,
    required this.gained,
    required this.mergedValue,
    required this.mergedCount,
    required this.cleared,
    this.repairedCells = 0,
  });
```

`BonusGrid` クラスの中に追加:

```dart
  /// 詰んでいれば修復した盤面を、詰んでいなければ自分自身を返す。
  ///
  /// 修復は**値が低いマスから順に引き直す**。25 マスすべてを引き直しても
  /// 合法手ができなければ、盤面全体を並べ替える。
  ///
  /// 全並べ替えを既定にしない理由は実測にある（仕様 §3.2）。全並べ替えは
  /// 1 回で 25 マス中 21.2 マスを書き換え、最大値のマスの位置を 99% の
  /// 確率で壊す。詰みは 8 タップに 1 回起きるので、それではプレイヤーが
  /// 積み上げたものが絶えず散らされる。低い値から引き直す方式は 3.0 マス
  /// しか変えず、最大値のマスは一度も動かなかった。
  ///
  /// 最後の全並べ替えは必ず成功する。25 マスに対して値は 10 種類以下
  /// なので鳩の巣原理により必ず重複があり、重複がある限りそれらを
  /// 隣接させる並べ替えが存在する。実測では 300 ゲーム・3,965 回の修復で
  /// ここへ到達した回数は 0 回だったが、引き直しの終了は確率に依存する
  /// ため、保証を運に委ねないよう残している。
  BonusRepair repairIfStuck(Random random) {
    if (hasLegalMove) return BonusRepair(this, 0);

    final next = List<int>.of(cells);
    final boardMax = maxValue;
    // 値が低い順。同値のマスの間の順序は乱数で散らす（毎回同じ隅から
    // 引き直して偏るのを避ける）。
    final order = List<int>.generate(kBonusCells, (i) => i)
      ..sort((a, b) {
        final byValue = cells[a].compareTo(cells[b]);
        return byValue != 0 ? byValue : random.nextInt(3) - 1;
      });

    for (final i in order) {
      next[i] = spawnValue(boardMax, random);
      final candidate = BonusGrid._(next);
      if (candidate.hasLegalMove) {
        return BonusRepair(candidate, _changedCells(cells, next));
      }
    }

    // ここへは実測で一度も到達していないが、引き直しの終了は確率に依存
    // するので、必ず成功する手段を最後に置く。
    final shuffled = List<int>.of(next);
    for (var attempt = 0; attempt < 1000; attempt++) {
      shuffled.shuffle(random);
      final candidate = BonusGrid._(shuffled);
      if (candidate.hasLegalMove) {
        return BonusRepair(candidate, _changedCells(cells, shuffled));
      }
    }
    throw StateError('盤面の修復に失敗した: $cells');
  }
```

`BonusGrid.of` の隣に追加:

```dart
  /// 新しいゲームの初期盤面を配る（仕様 §2.7）。
  ///
  /// 各マスを独立に 1..3 から引く。`spawnValue` に `boardMax = 4` を
  /// 渡すのがその範囲にあたる。
  ///
  /// **`boardMax = 1` で埋めてはいけない。** 補充の範囲は
  /// `1 .. max(1, boardMax - 1)` なので、1 では 25 マス全部が 1 になり、
  /// 最初のタップが 25 マスを一括マージして 2 を 1 個作るだけの退化した
  /// 開幕になる。
  ///
  /// 3 値であれば同値が隣接しない配置（3 彩色に相当する並び）が存在する
  /// ため、配った直後に詰み検査を通す。実測では 300 ゲーム中 0 回しか
  /// 作動しなかったが、検査は 1 回で済み、外した場合は開幕が完全に詰む。
  factory BonusGrid.deal(Random random) {
    final cells = List<int>.generate(kBonusCells, (_) => spawnValue(4, random));
    return BonusGrid._(cells).repairIfStuck(random).grid;
  }
```

`tap` の補充ループの直後、`return` の前に修復を挟む:

```dart
    final repair = BonusGrid._(next).repairIfStuck(random);

    return BonusMerge(
      grid: repair.grid,
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
      repairedCells: repair.changedCells,
    );
```

ファイル末尾（トップレベル）に追加:

```dart
/// 詰みの修復結果。
class BonusRepair {
  final BonusGrid grid;

  /// 修復で書き換えたマス数。0 なら詰んでいなかった。
  final int changedCells;

  const BonusRepair(this.grid, this.changedCells);
}

int _changedCells(List<int> before, List<int> after) {
  var count = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) count++;
  }
  return count;
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus/bonus_repair_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 6: コミット**

```bash
git add lib/domain/bonus/bonus_grid.dart test/domain/bonus/bonus_repair_test.dart
git commit -m "feat(bonus): repair deadlock by rerolling the lowest cells, keeping the top tile"
```

---

### Task 5: 1 日 1 回の権利

**Files:**
- Create: `lib/domain/bonus_ticket.dart`
- Test: `test/domain/bonus_ticket_test.dart`

**Interfaces:**
- Consumes: なし（盤面を知らない）
- Produces:
  - `const int kBonusUnlockClears = 5;`
  - `String bonusDateKey(DateTime local)` — `yyyy-MM-dd`
  - `class BonusTicket` — `BonusTicket({String? unlockedOn, String? playedOn})`、`String? get unlockedOn`、`String? get playedOn`、`bool earn(String today)`、`bool isAvailable(String today)`、`void consume(String today)`

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/bonus_ticket_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus_ticket.dart';

void main() {
  group('bonusDateKey', () {
    test('yyyy-MM-dd に整形する', () {
      expect(bonusDateKey(DateTime(2026, 9, 3)), '2026-09-03');
      expect(bonusDateKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(bonusDateKey(DateTime(2026, 1, 1, 23, 59, 59)), '2026-01-01');
    });

    test('日付が変わる瞬間で切り替わる', () {
      expect(bonusDateKey(DateTime(2026, 9, 3, 23, 59, 59)), '2026-09-03');
      expect(bonusDateKey(DateTime(2026, 9, 4, 0, 0, 0)), '2026-09-04');
    });
  });

  group('解禁条件', () {
    test('5 問が必要', () {
      expect(kBonusUnlockClears, 5);
    });
  });

  group('earn / isAvailable', () {
    test('初期状態では遊べない', () {
      final ticket = BonusTicket();
      expect(ticket.isAvailable('2026-09-03'), isFalse);
    });

    test('earn すると遊べるようになる', () {
      final ticket = BonusTicket();
      expect(ticket.earn('2026-09-03'), isTrue);
      expect(ticket.isAvailable('2026-09-03'), isTrue);
    });

    test('同じ日の 2 回目の earn は何も変えない', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      expect(ticket.earn('2026-09-03'), isFalse,
          reason: '2 回目の earn が「新しく解禁した」と報告している');
      expect(ticket.isAvailable('2026-09-03'), isTrue);
    });

    test('遊んだ後は同じ日にもう遊べない', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      ticket.consume('2026-09-03');
      expect(ticket.isAvailable('2026-09-03'), isFalse);
    });

    test('遊んだ後に 5 問クリアしても権利は復活しない', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      ticket.consume('2026-09-03');
      expect(ticket.earn('2026-09-03'), isFalse);
      expect(ticket.isAvailable('2026-09-03'), isFalse,
          reason: '1 日 1 回の制限が破れている');
    });
  });

  group('日付をまたぐ', () {
    test('繰り越さない（今日とった権利は今日のもの）', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      expect(ticket.isAvailable('2026-09-04'), isFalse,
          reason: '前日の権利が翌日に残っている');
    });

    test('翌日はまた解禁できる', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      ticket.consume('2026-09-03');
      expect(ticket.earn('2026-09-04'), isTrue);
      expect(ticket.isAvailable('2026-09-04'), isTrue);
    });

    test('前日に遊んでいても翌日の解禁を邪魔しない', () {
      final ticket = BonusTicket(unlockedOn: '2026-09-03', playedOn: '2026-09-03');
      expect(ticket.earn('2026-09-04'), isTrue);
      expect(ticket.isAvailable('2026-09-04'), isTrue);
    });
  });

  group('復元', () {
    test('保存した値から状態を復元できる', () {
      final ticket = BonusTicket(unlockedOn: '2026-09-03', playedOn: null);
      expect(ticket.isAvailable('2026-09-03'), isTrue);
      expect(ticket.unlockedOn, '2026-09-03');
      expect(ticket.playedOn, isNull);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus_ticket_test.dart`
Expected: FAIL — `bonus_ticket.dart` が存在しない

- [ ] **Step 3: 実装を書く**

`lib/domain/bonus_ticket.dart`:

```dart
/// ボーナスゲームが解禁されるまでに必要な、タイムアタック 1 回でのクリア数。
///
/// 難易度は問わない（easy / normal / hard のいずれでも 5 問）。無料の
/// 1 日 1 回の報酬なので easy での稼ぎを害と見なさず、ルールが一行で
/// 説明できることを優先した（仕様 §4.1）。
const int kBonusUnlockClears = 5;

/// ローカル日付を `yyyy-MM-dd` に整形する。
///
/// 権利の管理に整数の秒やミリ秒を使わないのが要点。サマータイムや端末の
/// 時刻変更で日付境界の判定が壊れるため、初めから「日」を単位にする
/// （仕様 §4.2）。
String bonusDateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

/// ボーナスゲームを「今日まだ遊べるか」だけを判定する、プラットフォーム
/// 非依存の純粋なロジック。盤面のルールを一切知らない。
///
/// 保存はしない（既存 `AdPolicy` と同じ考え方）。呼び出し側が
/// [unlockedOn] / [playedOn] を読み出して永続化し、次回起動時に
/// コンストラクタへ渡し直す。
class BonusTicket {
  String? _unlockedOn;
  String? _playedOn;

  BonusTicket({String? unlockedOn, String? playedOn})
      : _unlockedOn = unlockedOn,
        _playedOn = playedOn;

  /// 最後に解禁条件を満たした日。
  String? get unlockedOn => _unlockedOn;

  /// 最後にボーナスゲームを開始した日。
  String? get playedOn => _playedOn;

  /// 解禁条件を満たしたときに呼ぶ。**新しく遊べるようになったら** true。
  ///
  /// その日すでに遊んでいれば何もしない。ここで解禁し直せてしまうと、
  /// 「タイムアタックで 5 問クリア → ボーナス → また 5 問クリア」で
  /// 1 日に何度でも遊べてしまう。
  bool earn(String today) {
    if (_playedOn == today) return false;
    if (_unlockedOn == today) return false;
    _unlockedOn = today;
    return true;
  }

  /// 今日ボーナスゲームを遊べるか。
  ///
  /// 権利は繰り越さない。前日に解禁して遊ばなかった場合、翌日には
  /// `_unlockedOn != today` になって消える（仕様 §4.2）。
  bool isAvailable(String today) =>
      _unlockedOn == today && _playedOn != today;

  /// ボーナスゲームを**開始した**ときに呼ぶ。
  ///
  /// 完了時ではなく開始時に消費する。完了時にすると、強制終了することで
  /// 無限にリトライできてしまう（仕様 §4.3）。中断で権利を失う実害は、
  /// 途中の盤面を永続化して再開できるようにすることで消している。
  void consume(String today) {
    _playedOn = today;
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus_ticket_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 6: コミット**

```bash
git add lib/domain/bonus_ticket.dart test/domain/bonus_ticket_test.dart
git commit -m "feat(bonus): gate the bonus game to one play per local day"
```

---

### Task 6: ドメイン層の Flutter 非依存を機械的に検査する

**Files:**
- Create: `test/domain/domain_purity_test.dart`

**Interfaces:**
- Consumes: なし（ソースを文字列として読むだけ）
- Produces: なし

**このタスクが必要な理由:** `lib/domain/` の Flutter 非依存は、これまで `tool/generate_puzzles.dart` が `dart run` でコンパイルされることで**間接的に**保証されていた（`package:flutter` を import したファイルは `dart run` で落ちる）。しかしそのスクリプトは `solver.dart` / `puzzle.dart` / `difficulty.dart` / `operation.dart` しか import しないので、**`lib/domain/bonus/` と `bonus_ticket.dart` はこの保証の外にある。** 明示的に検査する。

- [ ] **Step 1: 失敗するテストを書く**

`test/domain/domain_purity_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/domain/` は Flutter に依存しない、という規約を機械的に見張る。
///
/// これまでこの規約は `tool/generate_puzzles.dart` が `dart run` で
/// コンパイルされることで間接的に守られていた（`package:flutter` を
/// import したファイルは素の `dart run` で落ちる）。ただしその経路が
/// カバーするのは、あのスクリプトが実際に import しているファイルだけ
/// である。ドメイン層に新しいファイルが増えるとカバー範囲から静かに
/// 外れるので、ここでディレクトリ全体を見る。
void main() {
  test('lib/domain/ は package:flutter を import しない', () {
    final dir = Directory('lib/domain');
    expect(dir.existsSync(), isTrue, reason: 'lib/domain/ が見つからない');

    final offenders = <String>[];
    final checked = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      checked.add(path);
      final source = entity.readAsStringSync();
      for (final line in source.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('package:flutter/') ||
            trimmed.contains('package:flutter_test/')) {
          offenders.add('$path: $trimmed');
        }
      }
    }

    expect(checked, isNotEmpty, reason: '.dart ファイルが 1 つも見つからない');
    expect(
      offenders,
      isEmpty,
      reason: 'lib/domain/ 配下が Flutter に依存している。ドメイン層は '
          '`dart run` だけで動く純粋な Dart に保つ:\n${offenders.join('\n')}',
    );
  });
}
```

- [ ] **Step 2: テストが「今の状態では通る」ことを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/domain_purity_test.dart`
Expected: PASS（1 test）

これは既存コードが既に規約を守っているので当然通る。**次の Step で、検査が本当に効くことを確かめる。**

- [ ] **Step 3: 検査が実際に違反を捕まえることを確認する**

`lib/domain/bonus/spawn_rule.dart` の 1 行目に一時的に次を挿入する:

```dart
import 'package:flutter/foundation.dart';
```

Run: `C:/flutter/bin/flutter.bat test test/domain/domain_purity_test.dart`
Expected: **FAIL** — `lib/domain/bonus/spawn_rule.dart: import 'package:flutter/foundation.dart';` が offenders に出る

確認できたら**その 1 行を必ず削除する**。削除後に再度実行して PASS に戻ることを確認:

Run: `C:/flutter/bin/flutter.bat test test/domain/domain_purity_test.dart`
Expected: PASS

- [ ] **Step 4: `git status` で余計な変更が残っていないことを確認**

Run: `git status --porcelain lib/domain/`
Expected: 出力なし（Step 3 の一時的な import が消えている）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 6: コミット**

```bash
git add test/domain/domain_purity_test.dart
git commit -m "test(domain): assert the whole domain layer stays free of Flutter imports"
```

---

## 残りのタスク

Task 7 以降（永続化・セッション・UI・実測の再現）は分量が大きいため、
[2026-09-03-make10-bonus-game-part2.md](2026-09-03-make10-bonus-game-part2.md) に続く。

- Task 7: `BonusRepository`（`make10.bonus` への永続化、壊れたデータの扱い）
- Task 8: `BonusSession`（ChangeNotifier、dispose ガード、途中保存）
- Task 9: Riverpod プロバイダと `BonusGridView`（320pt 幅での破綻防止）
- Task 10: `BonusGameScreen` / `BonusResultScreen`
- Task 11: ホーム画面の 4 状態
- Task 12: タイムアタックのリザルトでの解禁と `earn` の配線
- Task 13: 統計画面へのベストスコア追加
- Task 14: `tool/simulate_bonus.dart` で仕様 §3.1 の実測値を実エンジンで再現
