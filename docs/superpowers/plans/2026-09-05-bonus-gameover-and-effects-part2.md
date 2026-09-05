# ボーナスゲーム 敗北条件とエフェクト 実装計画 (後半)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

[前半 (Task 1〜3)](2026-09-05-bonus-gameover-and-effects.md) の続き。**Global Constraints は前半のものがそのまま適用される。**

前半で作られたもの:

```dart
// lib/domain/bonus/bonus_grid.dart
const int kBonusRepairLimit = 10;

BonusMerge? tap(int index, Random random, {bool repairIfStuck = true});

class BonusMerge {
  BonusGrid get grid;
  int get gained;
  int get mergedValue;
  int get mergedCount;
  bool get cleared;
  int get repairedCells;
  bool get usedFullShuffle;
  bool get isStuck;          // 修復を断って詰んだ
  Set<int> get removedCells; // 消えたマス（手を打つ前の座標）
  Map<int,int> get fallenCells; // 打つ前の添字 → 打った後の添字
  Set<int> get spawnedCells; // 湧いたマス（打った後の座標）
  int get mergedInto;        // n+1 になったマスの、打った後の位置
}

// lib/game/bonus_session.dart
enum BonusOutcome { cleared, gameOver, gaveUp }

class BonusSession extends ChangeNotifier {
  BonusSession({required BonusRepository repository, required BonusGrid grid,
                required int score, int repairsUsed = 0, Random? random});
  BonusOutcome? get outcome;   // 終わっていなければ null
  bool get isOver;
  bool get isCleared;
  bool get isGameOver;
  int get repairsUsed;
  int get repairsLeft;
  int get lastRepairedCells;
  BonusGrid get grid;
  int get score;
  int get bestScore;
  bool get bestUpdated;
  bool get isSavingResult;
  void tap(int index);
  void giveUp();
}
```

---

### Task 4: `repairsUsed` を永続化する

**Files:**
- Modify: `lib/data/bonus_repository.dart`
- Modify: `lib/game/bonus_session.dart`（`saveProgress` の呼び出しに第 3 引数）
- Modify: `lib/ui/home_screen.dart`（再開時に `repairsUsed` を渡す）
- Test: `test/data/bonus_repairs_persist_test.dart`

**Interfaces:**
- Consumes: `kBonusRepairLimit`
- Produces:
  - `BonusRepository` に `int get inProgressRepairsUsed`
  - `Future<void> saveProgress(BonusGrid grid, int score, int repairsUsed)`

**これは抜け道を塞ぐタスク:** 保存しないと、中断して再開するたびに入れ替えが 10 回に戻る。ゲームオーバーが実質的に起こらなくなり、Task 3 の変更がまるごと無意味になる。

- [ ] **Step 1: 失敗するテストを書く**

`test/data/bonus_repairs_persist_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid playableGrid() => BonusGrid.of(const [
      1, 1, 3, 1, 2, //
      3, 1, 2, 3, 1, //
      2, 3, 1, 2, 3, //
      1, 2, 3, 1, 2, //
      3, 1, 2, 3, 1, //
    ]);

Future<BonusRepository> loaded() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('開始直後は 0', () async {
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    expect(repo.inProgressRepairsUsed, 0);
  });

  test('保存して読み直せる', () async {
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    await repo.saveProgress(playableGrid(), 340, 6);

    final reloaded = await loaded();
    expect(reloaded.inProgressRepairsUsed, 6);
    expect(reloaded.inProgressScore, 340);
  });

  test('中断して再開しても入れ替えの残りが戻らない', () async {
    // 抜け道の本体。ここが通らないと Task 3 の上限が意味を失う。
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    await repo.saveProgress(playableGrid(), 500, kBonusRepairLimit);

    final reloaded = await loaded();
    expect(reloaded.inProgressRepairsUsed, kBonusRepairLimit,
        reason: '再開で入れ替えの使用回数がリセットされている');
  });

  test('終了で 0 に戻る', () async {
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    await repo.saveProgress(playableGrid(), 500, 8);
    await repo.finish(500);
    expect(repo.inProgressRepairsUsed, 0);

    final reloaded = await loaded();
    expect(reloaded.inProgressRepairsUsed, 0);
    expect(reloaded.hasInProgress, isFalse);
  });

  group('壊れた・古いデータ', () {
    test('repairsUsed が無い古い保存データは 0 として読む', () async {
      // 上限を入れる前に保存された途中状態。捨ててゲームを失わせるより、
      // 上限が緩む方に倒す（仕様 §7）。
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'bestScore': 700,
          'playedOn': '2026-09-05',
          'inProgress': {'grid': playableGrid().cells, 'score': 120},
        }),
      });
      final repo = await loaded();
      expect(repo.hasInProgress, isTrue);
      expect(repo.inProgressRepairsUsed, 0);
      expect(repo.inProgressScore, 120);
    });

    test('負の値は 0 に丸める', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': playableGrid().cells,
            'score': 10,
            'repairsUsed': -5,
          },
        }),
      });
      final repo = await loaded();
      expect(repo.inProgressRepairsUsed, 0);
    });

    test('上限を超える値は上限に丸める', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': playableGrid().cells,
            'score': 10,
            'repairsUsed': 999,
          },
        }),
      });
      final repo = await loaded();
      expect(repo.inProgressRepairsUsed, kBonusRepairLimit);
    });

    test('型が違えば 0 として読む', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': playableGrid().cells,
            'score': 10,
            'repairsUsed': 'たくさん',
          },
        }),
      });
      final repo = await loaded();
      // 途中状態ごと捨てるか 0 として読むかは実装次第だが、例外を
      // 外へ投げてはいけない。
      expect(repo.inProgressRepairsUsed, 0);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_repairs_persist_test.dart`
Expected: FAIL — `inProgressRepairsUsed` が未定義

- [ ] **Step 3: `lib/data/bonus_repository.dart` を変更する**

フィールドと getter を足す。

```dart
  int _inProgressRepairsUsed = 0;
```

```dart
  /// 中断した局面までに盤面を入れ替えた回数。
  ///
  /// **保存しないと、中断・再開のたびに入れ替えが上限まで戻る。**
  /// 上限（[kBonusRepairLimit]）が事実上無くなり、ゲームオーバーが
  /// 起こらなくなるので、これは仕様の穴ではなく抜け道になる（仕様 §3.4）。
  int get inProgressRepairsUsed => _inProgressRepairsUsed;
```

`load()` の中、`score` を読む行の隣を変える。

```dart
    var score = 0;
    var repairsUsed = 0;
```

```dart
          try {
            grid = _decodeGrid(inProgress['grid']);
            score = inProgress['score'] as int? ?? 0;
            // 上限を入れる前の保存データには repairsUsed が無い。捨てて
            // ゲームを失わせるより、0（上限が緩む側）に倒す（仕様 §7）。
            final raw = inProgress['repairsUsed'];
            repairsUsed = raw is int ? raw.clamp(0, kBonusRepairLimit) : 0;
          } catch (_) {
            grid = null;
            score = 0;
            repairsUsed = 0;
          }
```

外側の catch でも `repairsUsed = 0;` を足す。末尾の代入にも足す。

```dart
    _inProgressRepairsUsed = repairsUsed;
```

`startGame` / `saveProgress` / `finish` / `_writeNow` を変える。

```dart
  Future<void> startGame(String today, BonusGrid grid) async {
    _ticket.consume(today);
    _inProgressGrid = grid;
    _inProgressScore = 0;
    _inProgressRepairsUsed = 0;
    await _save();
    notifyListeners();
  }

  Future<void> saveProgress(BonusGrid grid, int score, int repairsUsed) async {
    _inProgressGrid = grid;
    _inProgressScore = score;
    _inProgressRepairsUsed = repairsUsed.clamp(0, kBonusRepairLimit);
    await _save();
    notifyListeners();
  }
```

`finish` に `_inProgressRepairsUsed = 0;` を足す。

`_writeNow` の `inProgress` を変える。

```dart
        if (grid != null)
          'inProgress': {
            'grid': grid.cells,
            'score': _inProgressScore,
            'repairsUsed': _inProgressRepairsUsed,
          },
```

- [ ] **Step 4: 呼び出し側を合わせる**

`lib/game/bonus_session.dart` の `tap` の中:

```dart
      repository.saveProgress(_grid, _score, _repairsUsed).ignore();
```

`lib/ui/home_screen.dart` の `_BonusEntry._start` で、再開時に渡す。
`BonusSession(...)` の呼び出しに引数を足す。

```dart
    final session = BonusSession(
      repository: bonus,
      grid: grid,
      score: score,
      repairsUsed: bonus.inProgressRepairsUsed,
    );
```

新規開始の場合、`startGame` が `_inProgressRepairsUsed` を 0 にしてから
読むので 0 になる。**`startGame` の後に読むこと**（順序を逆にすると
前回のゲームの値が残る）。

- [ ] **Step 5: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_repairs_persist_test.dart`
Expected: PASS

- [ ] **Step 6: 抜け道が実際に塞がっていることを確認する**

`saveProgress` の `_inProgressRepairsUsed = repairsUsed.clamp(...)` を
一時的に `_inProgressRepairsUsed = 0;` に変える。

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_repairs_persist_test.dart`
Expected: **FAIL** — 「中断して再開しても入れ替えの残りが戻らない」が落ちる

確認したら元に戻し、再実行して PASS を確認する。

- [ ] **Step 7: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。既存の `test/data/bonus_repository_test.dart` は
`saveProgress` を 2 引数で呼んでいるので**コンパイルが通らなくなる**。
第 3 引数 `0` を足して直すこと。これは既存テストの意図を変えない
機械的な修正である。

- [ ] **Step 8: コミット**

```bash
git add lib/data/bonus_repository.dart lib/game/bonus_session.dart lib/ui/home_screen.dart test/data/bonus_repairs_persist_test.dart test/data/bonus_repository_test.dart
git commit -m "feat(bonus): persist the repair count so resuming cannot refill it"
```

---

### Task 5: 残り回数の表示・ゲームオーバー画面・結果の 3 状態

**Files:**
- Modify: `lib/ui/bonus_result_screen.dart`（`cleared` → `outcome`）
- Modify: `lib/ui/bonus_game_screen.dart`（残り回数、ゲームオーバーの重ね表示）
- Test: `test/ui/bonus_gameover_screen_test.dart`

**Interfaces:**
- Consumes: `BonusOutcome`、`BonusSession.repairsLeft` / `isGameOver`
- Produces: `BonusResultScreen({required BonusOutcome outcome, ...})`

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_gameover_screen_test.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/game/bonus_session.dart';
import 'package:make10/ui/bonus_game_screen.dart';
import 'package:make10/ui/bonus_result_screen.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

Future<BonusSession> sessionWith(
  BonusGrid grid, {
  int score = 0,
  int repairsUsed = 0,
  int seed = 0,
}) async {
  final repo = BonusRepository();
  await repo.load();
  return BonusSession(
    repository: repo,
    grid: grid,
    score: score,
    repairsUsed: repairsUsed,
    random: Random(seed),
  );
}

Future<void> pumpGame(WidgetTester tester, BonusSession session) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(home: BonusGameScreen(session: session, onExit: () {})),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('残り回数の表示', () {
    testWidgets('最初は上限いっぱいを出す', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      expect(find.text('入れ替え $kBonusRepairLimit'), findsOneWidget);
    });

    testWidgets('使った分だけ減って見える', (tester) async {
      await pumpGame(
        tester,
        await sessionWith(fiveTwosGrid(), repairsUsed: 4),
      );
      expect(find.text('入れ替え ${kBonusRepairLimit - 4}'), findsOneWidget);
    });

    testWidgets('残り 0 では次で終わることを伝える', (tester) async {
      await pumpGame(
        tester,
        await sessionWith(fiveTwosGrid(), repairsUsed: kBonusRepairLimit),
      );
      expect(find.text('入れ替え 0'), findsOneWidget);
      expect(find.textContaining('次に詰んだら終わり'), findsOneWidget);
    });
  });

  group('ゲームオーバーの重ね表示', () {
    /// 入れ替えを使い切った状態から打ち続け、ゲームオーバーにする。
    ///
    /// 詰みは 8 タップに 1 回起きるので、残り 0 から打てばすぐ終わる。
    /// 終わらなければテスト側の前提が壊れているので、はっきり失敗させる。
    Future<BonusSession> playToGameOver({int seed = 0}) async {
      for (var s = seed; s < seed + 30; s++) {
        final session = await sessionWith(
          BonusGrid.deal(Random(s)),
          repairsUsed: kBonusRepairLimit,
          seed: s,
        );
        for (var move = 0; move < 200 && !session.isOver; move++) {
          final tappable = [
            for (var i = 0; i < kBonusCells; i++)
              if (session.grid.canTap(i)) i,
          ];
          if (tappable.isEmpty) break;
          session.tap(tappable.first);
        }
        if (session.isGameOver) return session;
        session.dispose();
      }
      fail('入れ替えの残り 0 から 30 シード試してもゲームオーバーにならなかった');
    }

    testWidgets('盤面を出したまま重ねる', (tester) async {
      final session = await playToGameOver();
      await pumpGame(tester, session);
      expect(find.text('ゲームオーバー'), findsOneWidget);
      expect(find.text('打つ手がありません'), findsOneWidget);
      // 自分を詰ませた盤面が見えていることが、この表示の目的そのもの。
      expect(find.byType(BonusGridView), findsOneWidget);
      // まだ結果画面ではない。
      expect(find.byType(BonusResultScreen), findsNothing);
    });

    testWidgets('「結果へ」で結果画面に進む', (tester) async {
      final session = await playToGameOver();
      await pumpGame(tester, session);
      await tester.tap(find.text('結果へ'));
      await tester.pumpAndSettle();
      expect(find.byType(BonusResultScreen), findsOneWidget);
      expect(find.byType(BonusGridView), findsNothing);
    });

    testWidgets('クリアでは重ねずに直接結果画面へ行く', (tester) async {
      // クリアと「やめる」はプレイヤー自身の行為なので、なぜ終わったかを
      // 見せる段は要らない（仕様 §3.2）。
      final session = await sessionWith(gridOf([
        [9, 9, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]));
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
      await tester.pumpAndSettle();
      expect(find.byType(BonusResultScreen), findsOneWidget);
      expect(find.text('10 を作った!'), findsOneWidget);
      expect(find.text('結果へ'), findsNothing);
    });
  });

  group('結果画面の 3 状態', () {
    Future<void> pumpResult(WidgetTester tester, BonusOutcome outcome) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BonusResultScreen(
            score: 852,
            bestScore: 852,
            bestUpdated: true,
            isSaving: false,
            outcome: outcome,
            onHome: () {},
          ),
        ),
      );
    }

    testWidgets('クリア', (tester) async {
      await pumpResult(tester, BonusOutcome.cleared);
      expect(find.text('10 を作った!'), findsOneWidget);
      expect(find.text('ゲームオーバー'), findsNothing);
      expect(find.text('ここまで'), findsNothing);
    });

    testWidgets('ゲームオーバー', (tester) async {
      await pumpResult(tester, BonusOutcome.gameOver);
      expect(find.text('ゲームオーバー'), findsOneWidget);
      expect(find.text('10 を作った!'), findsNothing);
      expect(find.text('ここまで'), findsNothing);
    });

    testWidgets('やめた', (tester) async {
      await pumpResult(tester, BonusOutcome.gaveUp);
      expect(find.text('ここまで'), findsOneWidget);
      expect(find.text('10 を作った!'), findsNothing);
      expect(find.text('ゲームオーバー'), findsNothing);
    });

    testWidgets('どの終わり方でもスコアとベストは出る', (tester) async {
      for (final outcome in BonusOutcome.values) {
        await pumpResult(tester, outcome);
        expect(find.text('スコア 852'), findsOneWidget);
        expect(find.text('ベスト更新!'), findsOneWidget);
      }
    });
  });

  group('レイアウト', () {
    testWidgets('320pt 幅で溢れない', (tester) async {
      final session = await sessionWith(fiveTwosGrid(), repairsUsed: 7);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: BonusGameScreen(session: session, onExit: () {})),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_gameover_screen_test.dart`
Expected: FAIL — `BonusResultScreen` に `outcome` という引数が無い

- [ ] **Step 3: `lib/ui/bonus_result_screen.dart` を変更する**

import を追加する。

```dart
import '../game/bonus_session.dart' show BonusOutcome;
```

`final bool cleared;` を消して次に置き換える。

```dart
  /// このゲームの終わり方。見出しがこれで決まる（仕様 §3.2）。
  final BonusOutcome outcome;
```

コンストラクタの `required this.cleared,` を `required this.outcome,` に変える。

`build` の見出しを差し替える。

```dart
                Text(
                  switch (outcome) {
                    BonusOutcome.cleared => '10 を作った!',
                    BonusOutcome.gameOver => 'ゲームオーバー',
                    BonusOutcome.gaveUp => 'ここまで',
                  },
                  style: theme.textTheme.headlineMedium,
                ),
```

- [ ] **Step 4: `lib/ui/bonus_game_screen.dart` を変更する**

`BonusResultScreen` の呼び出しを変える。

```dart
          return BonusResultScreen(
            score: session.score,
            bestScore: session.bestScore,
            bestUpdated: session.bestUpdated,
            isSaving: session.isSavingResult,
            outcome: session.outcome!,
            onHome: onExit,
          );
```

`session.isOver` が真のときだけこの枝に入るので、`outcome` は非 null。

スコア行の Row に残り回数を足す。

```dart
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('スコア ${session.score}',
                          style: theme.textTheme.headlineSmall),
                      Row(
                        children: [
                          Text('最大 ${session.grid.maxValue}',
                              style: theme.textTheme.titleMedium),
                          SizedBox(width: 12 * scale),
                          // 入れ替えは有限資源になったので常時出す。残りが
                          // 見えないと「なぜ負けたか」も「あと何回耐えられ
                          // るか」も分からない（仕様 §3.3）。
                          Text(
                            '入れ替え ${session.repairsLeft}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: session.repairsLeft <= 3
                                  ? theme.colorScheme.error
                                  : null,
                              fontWeight: session.repairsLeft <= 3
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
```

通知のスロットを、残り 0 のときの警告も出せるように変える。

```dart
                  SizedBox(
                    height: 20 * scale,
                    child: session.repairsLeft == 0
                        ? Text(
                            '入れ替えを使い切りました。次に詰んだら終わりです',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          )
                        : session.lastRepairedCells > 0
                            ? Text(
                                '打てる手が無くなったので'
                                '${session.lastRepairedCells} マス入れ替えました',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary),
                              )
                            : const SizedBox.shrink(),
                  ),
```

ゲームオーバーの重ね表示は、盤面の `Expanded` を `Stack` で包む。

```dart
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: BonusGridView(
                            grid: session.grid,
                            onTapCell: session.tap,
                          ),
                        ),
                        if (session.isGameOver)
                          _GameOverOverlay(
                            score: session.score,
                            onResult: () {},
                          ),
                      ],
                    ),
                  ),
```

**ただしこの分岐には入らない。** `session.isGameOver` が真なら
`session.isOver` も真で、build の先頭で結果画面に差し替わっているためである。
重ね表示を出すには、結果画面へ進むかどうかを画面側の状態として持つ必要が
ある。`BonusGameScreen` を `StatefulWidget` にして、「ゲームオーバーを
見せ終えたか」を持つ。

```dart
class BonusGameScreen extends StatefulWidget {
  final BonusSession session;
  final VoidCallback onExit;

  const BonusGameScreen({
    super.key,
    required this.session,
    required this.onExit,
  });

  @override
  State<BonusGameScreen> createState() => _BonusGameScreenState();
}

class _BonusGameScreenState extends State<BonusGameScreen> {
  /// ゲームオーバーの重ね表示を見終えて、結果画面へ進んだか。
  ///
  /// ゲームオーバーで即座に結果画面へ飛ばすと、**なぜ負けたのかが
  /// 見えない**。修復はこれまで一瞬で自動的に行われてきたので、
  /// プレイヤーは自分を詰ませた盤面を一度見て初めて因果を理解できる
  /// （仕様 §3.2）。クリアと「やめる」はプレイヤー自身の行為なので
  /// この段は挟まず、今までどおり直接結果画面へ進む。
  bool _gameOverAcknowledged = false;
  ...
}
```

`build` の先頭の条件を次にする。

```dart
        final session = widget.session;
        final showResult = session.isOver &&
            (!session.isGameOver || _gameOverAcknowledged);
        if (showResult) {
          return BonusResultScreen(...);
        }
```

重ね表示の `onResult` は
`() => setState(() => _gameOverAcknowledged = true)` にする。

`_confirmGiveUp` の中の `session` は `widget.session` に変える。

ファイル末尾に重ね表示を足す。

```dart
/// 盤面の上に重ねるゲームオーバーの表示。
class _GameOverOverlay extends StatelessWidget {
  final int score;
  final VoidCallback onResult;

  const _GameOverOverlay({required this.score, required this.onResult});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      // 盤面を隠しきらない程度に落とす。自分を詰ませた盤面が見えている
      // ことが、この表示の目的そのものなので不透明にはしない。
      color: theme.colorScheme.surface.withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ゲームオーバー', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('打つ手がありません', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text('スコア $score', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          FilledButton(onPressed: onResult, child: const Text('結果へ')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 既存の呼び出しを直す**

`test/ui/bonus_game_screen_test.dart` が `BonusResultScreen(... cleared: ...)`
を使っている。`outcome: BonusOutcome.cleared` / `BonusOutcome.gaveUp` に
機械的に置き換える。**アサーションの意図は変えないこと。**

- [ ] **Step 6: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_gameover_screen_test.dart`
Expected: PASS

- [ ] **Step 7: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass

- [ ] **Step 8: コミット**

```bash
git add lib/ui/bonus_result_screen.dart lib/ui/bonus_game_screen.dart test/ui/bonus_gameover_screen_test.dart test/ui/bonus_game_screen_test.dart
git commit -m "feat(bonus): show the repair budget and the board that beat you"
```

---

### Task 6: 消滅と落下のアニメーション

**Files:**
- Modify: `lib/game/bonus_session.dart`（`lastMerge` と `moveCount` を公開）
- Modify: `lib/ui/widgets/bonus_grid_view.dart`（`StatefulWidget` にしてアニメーション）
- Modify: `lib/ui/bonus_game_screen.dart`（`BonusGridView` に渡す）
- Test: `test/ui/widgets/bonus_animation_test.dart`

**Interfaces:**
- Consumes: `BonusMerge.removedCells` / `fallenCells` / `spawnedCells` / `mergedInto`
- Produces:
  - `BonusSession` に `BonusMerge? get lastMerge`、`int get moveCount`
  - `BonusGridView({required BonusGrid grid, required void Function(int) onTapCell, BonusMerge? lastMerge, int moveSerial = 0})`

**設計の要点:** 描くのは常に**現在の論理盤面**。アニメーションはその上の
装飾に過ぎない。落ちてきたマスは `Transform.translate` で「元いた位置」から
定位置へ寄せて描き、消えたマスだけを別レイヤーの幽霊として重ねる。
`Transform` はレイアウトに影響しないので、320pt で溢れたら今までどおり
`RenderFlex` が声を上げる（`Stack` + `Positioned` に組み替えるとこの
安全網を失う）。

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/widgets/bonus_animation_test.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/game/bonus_session.dart';
import 'package:make10/ui/bonus_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// (1,0)(1,1)(1,2)(2,1)(2,2) の 2 が 5 マス連結する。
BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

Future<BonusSession> makeSession({int seed = 0}) async {
  final repo = BonusRepository();
  await repo.load();
  return BonusSession(
    repository: repo,
    grid: fiveTwosGrid(),
    score: 0,
    random: Random(seed),
  );
}

Future<void> pumpGame(
  WidgetTester tester,
  BonusSession session, {
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: BonusGameScreen(session: session, onExit: () {}),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('論理状態はアニメーションを待たない', () {
    testWidgets('タップした直後にスコアが確定する', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      // pump を 1 フレームだけ。アニメーションはまだ終わっていない。
      await tester.pump();
      expect(session.score, 10);
      expect(find.text('スコア 10'), findsOneWidget);
    });

    testWidgets('アニメーション中のタップが受け付けられる', (tester) async {
      // 92 タップのゲームで 1 手ごとに 300ms 待たせると 28 秒の待ち時間に
      // なる。連打しても手が落ちないことが要点（仕様 §4.1）。
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60)); // 消滅の途中
      final mid = session.score;

      // 打てるマスを探して、もう 1 手打つ。
      final next = [
        for (var i = 0; i < kBonusCells; i++)
          if (session.grid.canTap(i)) i,
      ].first;
      await tester.tap(find.byKey(ValueKey('bonus-cell-$next')));
      await tester.pump();
      expect(session.score, greaterThan(mid),
          reason: 'アニメーション中のタップが捨てられている');
      await tester.pumpAndSettle();
    });
  });

  group('アニメーションの尺', () {
    testWidgets('300ms で落ち着く', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      // 合計 300ms（消滅 120 + 落下 180）。余裕を見て 400ms 進めれば
      // 止まっているはず。
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: '400ms 経ってもアニメーションが続いている');
    });
  });

  group('disableAnimations', () {
    testWidgets('立っていればアニメーションを飛ばす', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session, disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'disableAnimations でもアニメーションが走っている');
      expect(session.score, 10);
    });
  });

  group('レイアウトの安全網', () {
    testWidgets('アニメーション中でも 320pt で溢れない', (tester) async {
      final session = await makeSession();
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: BonusGameScreen(session: session, onExit: () {})),
      );
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('アニメーション中も全マスがタップできる', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60));
      for (var i = 0; i < kBonusCells; i++) {
        expect(find.byKey(ValueKey('bonus-cell-$i')), findsOneWidget,
            reason: 'アニメーション中に添字 $i のマスが消えている');
      }
      await tester.pumpAndSettle();
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/widgets/bonus_animation_test.dart`
Expected: FAIL — アニメーションが無いので「300ms で落ち着く」は通るが、
`disableAnimations` のテストも通ってしまう。**まず「アニメーションの尺」
のテストが意味を持つよう、実装後に確認すること。**

- [ ] **Step 3: `lib/game/bonus_session.dart` に直近の手を公開する**

フィールドを足す。

```dart
  BonusMerge? _lastMerge;
  int _moveCount = 0;
```

getter を足す。

```dart
  /// 直近に成立した手。まだ 1 手も打っていなければ null。
  ///
  /// 盤面のアニメーションが「何がどこへ動いたか」を必要とする。前後の
  /// 盤面を差分しても同値のマスの対応が復元できないので、盤面が返した
  /// ものをそのまま渡す（仕様 §4.3）。
  BonusMerge? get lastMerge => _lastMerge;

  /// 成立した手の数。[lastMerge] の中身が同じでも手が進んだことを
  /// 見分けるために使う（アニメーションの再生の引き金）。
  int get moveCount => _moveCount;
```

`tap` の中、`if (merge == null) return;` の直後に足す。

```dart
    _lastMerge = merge;
    _moveCount++;
```

- [ ] **Step 4: `lib/ui/widgets/bonus_grid_view.dart` をアニメーション対応にする**

`BonusGridView` を `StatefulWidget` に変える。既存の
`BonusCellTile` と色の計算部分（`_kBonusLightness` 以下）は**そのまま
残す**。

```dart
/// 消滅にかける時間。
const Duration _kVanishDuration = Duration(milliseconds: 120);

/// 落下にかける時間。
const Duration _kFallDuration = Duration(milliseconds: 180);

/// 1 手ぶんのアニメーション全体。
const Duration _kMoveDuration = Duration(milliseconds: 300);

/// 全体に占める消滅の割合。落下はこの後から始まる（重ねない）。
const double _kVanishFraction = 120 / 300;

class BonusGridView extends StatefulWidget {
  final BonusGrid grid;
  final void Function(int index) onTapCell;

  /// 直近の手。アニメーションの内容はここから取る。null なら静止して描く。
  final BonusMerge? lastMerge;

  /// 手が進んだことを見分けるための通し番号（[BonusSession.moveCount]）。
  /// これが変わったらアニメーションを頭から再生する。
  final int moveSerial;

  const BonusGridView({
    super.key,
    required this.grid,
    required this.onTapCell,
    this.lastMerge,
    this.moveSerial = 0,
  });

  @override
  State<BonusGridView> createState() => _BonusGridViewState();
}

class _BonusGridViewState extends State<BonusGridView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kMoveDuration,
  );

  /// アニメーションに使う手。[widget.lastMerge] をそのまま見ないのは、
  /// 再生の途中で次の手が来たときに、いま再生中の手を最後まで持って
  /// いなくてよいから — 新しい手が来たら即座に差し替える（仕様 §4.1）。
  BonusMerge? _playing;

  @override
  void didUpdateWidget(BonusGridView old) {
    super.didUpdateWidget(old);
    if (widget.moveSerial == old.moveSerial) return;
    // 手が進んだ。再生中でも構わず頭から差し替える。論理盤面は既に
    // 新しいものになっているので、表示が一瞬飛んでも状態はずれない。
    _playing = widget.lastMerge;
    if (_reduceMotion) {
      _controller.value = 1.0;
    } else {
      _controller.forward(from: 0);
    }
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 添字 [i] の左上の座標。
  Offset _positionOf(int i, double cell) => Offset(
        (i % kBonusSize) * cell,
        (i ~/ kBonusSize) * cell,
      );

  /// 添字 [i] のマスを、いまどれだけずらして描くか。
  Offset _offsetFor(int i, double cell, double fallT) {
    final merge = _playing;
    if (merge == null || fallT >= 1.0) return Offset.zero;

    for (final entry in merge.fallenCells.entries) {
      if (entry.value != i) continue;
      final from = _positionOf(entry.key, cell);
      final to = _positionOf(i, cell);
      return (from - to) * (1 - fallT);
    }
    if (merge.spawnedCells.contains(i)) {
      // 盤面の上から滑り込ませる。行が下なほど長い距離を落ちる。
      final rows = (i ~/ kBonusSize) + 1;
      return Offset(0, -cell * rows * (1 - fallT));
    }
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 制約が無限のときは MediaQuery に落とす。Center の中など、
        // 高さが無制限で渡ってくる配置があるため。
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final side = maxWidth < maxHeight ? maxWidth : maxHeight;
        final cell = side / kBonusSize;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final vanishT = (t / _kVanishFraction).clamp(0.0, 1.0);
            final fallT = Curves.easeOut.transform(
              ((t - _kVanishFraction) / (1 - _kVanishFraction)).clamp(0.0, 1.0),
            );

            return SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  // 土台は常に現在の論理盤面。Transform はレイアウトに
                  // 影響しないので、寸法を誤れば今までどおり RenderFlex が
                  // 溢れて声を上げる。
                  Column(
                    children: [
                      for (var row = 0; row < kBonusSize; row++)
                        Row(
                          children: [
                            for (var col = 0; col < kBonusSize; col++)
                              Transform.translate(
                                offset: _offsetFor(
                                    row * kBonusSize + col, cell, fallT),
                                child: BonusCellTile(
                                  key: ValueKey(
                                      'bonus-cell-${row * kBonusSize + col}'),
                                  value: widget.grid.valueAt(row, col),
                                  size: cell,
                                  onTap: () =>
                                      widget.onTapCell(row * kBonusSize + col),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  // 消えたマスの幽霊。タップを奪わないよう IgnorePointer で
                  // 包む。
                  //
                  // `Positioned.fill` が要る。外側の Stack は既定で
                  // StackFit.loose なので、Positioned しか子を持たない
                  // 内側の Stack はサイズが決まらず潰れ、幽霊が 1 つも
                  // 描かれなくなる。
                  if (_playing != null && vanishT < 1.0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Stack(
                          children: [
                          for (final i in _playing!.removedCells)
                            Positioned(
                              left: _positionOf(i, cell).dx,
                              top: _positionOf(i, cell).dy,
                              child: Opacity(
                                opacity: 1 - vanishT,
                                child: Transform.scale(
                                  scale: 1 - vanishT * 0.6,
                                  child: BonusCellTile(
                                    value: _ghostValue(i),
                                    size: cell,
                                    onTap: () {},
                                  ),
                                ),
                              ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 幽霊に描く数字。消えたマスは連結成分なので、まとめた数字は 1 つ。
  int _ghostValue(int i) => _playing?.mergedValue ?? 1;
}
```

- [ ] **Step 5: `lib/ui/bonus_game_screen.dart` から渡す**

```dart
                          child: BonusGridView(
                            grid: session.grid,
                            onTapCell: session.tap,
                            lastMerge: session.lastMerge,
                            moveSerial: session.moveCount,
                          ),
```

- [ ] **Step 6: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/widgets/bonus_animation_test.dart`
Expected: PASS

- [ ] **Step 7: アニメーションが本当に走っていることを確認する**

`didUpdateWidget` の `_controller.forward(from: 0);` を一時的に
`_controller.value = 1.0;` に変える（＝常に即座に最終状態）。

Run: `C:/flutter/bin/flutter.bat test test/ui/widgets/bonus_animation_test.dart`
Expected: **FAIL** — 「300ms で落ち着く」テストは通ってしまうが、
アニメーションが走っていることを検査するテストが無いことになる。
**この場合、`tester.pump()` の直後に `hasScheduledFrame` が true である
ことを検査するテストを足すこと。** そのうえで、この変更で落ちることを
確認してから元に戻す。

- [ ] **Step 8: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。既存の
`test/ui/widgets/bonus_grid_view_test.dart` と
`test/ui/bonus_game_screen_test.dart` は `pumpAndSettle` を使っている
ものがある。アニメーションが入ったことで待ちが増えるだけなので通るはず
だが、落ちる場合は待ち方を直す（**アサーションの意図は変えない**）。

- [ ] **Step 9: コミット**

```bash
git add lib/game/bonus_session.dart lib/ui/widgets/bonus_grid_view.dart lib/ui/bonus_game_screen.dart test/ui/widgets/bonus_animation_test.dart
git commit -m "feat(bonus): animate cells vanishing and falling without blocking input"
```

---

### Task 7: 実測を取り直して仕様書を更新する

**Files:**
- Modify: `tool/simulate_bonus.dart`（上限を入れる）
- Modify: `test/tool/simulate_bonus_test.dart`
- Modify: `docs/superpowers/specs/2026-09-05-bonus-gameover-and-effects-design.md`（§6）

**Interfaces:**
- Consumes: `kBonusRepairLimit`、`BonusMerge.isStuck`
- Produces: `BonusSimResult` に `int wins`、`int gameOvers`

- [ ] **Step 1: シミュレータに上限を入れる**

`tool/simulate_bonus.dart` の `_play` を、セッションと同じ規則で回るように
変える。修復が起きた回数を数え、上限に達したら `repairIfStuck: false` を
渡し、`isStuck` が返ったらゲームオーバーとして終える。

```dart
    final merge = grid.tap(index, random,
        repairIfStuck: repairs < kBonusRepairLimit)!;
```

```dart
    if (merge.repairedCells > 0) repairs++;
    if (merge.isStuck) {
      return BonusSimRun(taps: taps, score: score, won: false, /* ... */);
    }
```

`BonusSimResult` にゲームオーバー数を足し、`main()` の出力に
「10 到達率」を出す。

- [ ] **Step 2: テストを更新する**

`test/tool/simulate_bonus_test.dart` の
`expect(result.wins, 300)`（全部 10 に到達する前提）は**もう成り立たない**。
仕様 §6 の 31.0% に合わせて、到達率が妥当な範囲に入ることを見る形へ変える。

```dart
    test('10 到達率が仕様 §6 の範囲に入る', () {
      final result = simulate(runs: 300, seed: 20260903, policy: 'score');
      // 仕様 §6: 31.0%。乱数実装が Python と違うので幅を持たせる。
      expect(result.wins / result.runs, closeTo(0.31, 0.10),
          reason: '実測 ${result.wins}/${result.runs}、仕様 31.0%');
      expect(result.wins + result.gameOvers, result.runs,
          reason: '勝ちでも負けでもない試行がある');
    }, timeout: const Timeout(Duration(minutes: 3)));
```

- [ ] **Step 3: 実行して数値を取る**

Run: `C:/flutter/bin/dart.bat run tool/simulate_bonus.dart 600 20260905`

**出力をパイプに通さないこと。** `tail` や `head` を挟むと非ゼロの終了
コードが隠れる（このプロジェクトで実際に踏んでいる）。終了コードを
明示的に確認する。

```bash
C:/flutter/bin/dart.bat run tool/simulate_bonus.dart 600 20260905; echo "exit=$?"
```

- [ ] **Step 4: 仕様書 §6 を Dart の実測値に差し替える**

`docs/superpowers/specs/2026-09-05-bonus-gameover-and-effects-design.md` の
§6 の表を、Step 3 で得た値に置き換える。**「Python で測った」という但し書きも
「Dart の実エンジンで測った」に直す。**

Python 側と大きく（10 ポイント以上）ずれた場合は、まず次を確認する。

1. シミュレータが `repairIfStuck: repairs < kBonusRepairLimit` を正しく渡しているか
2. `merge.repairedCells > 0` で修復回数を数えているか（`isStuck` の手では
   修復が起きていないので数えてはいけない）
3. `BonusGrid.deal` の配り直しを修復回数に数えていないか（仕様 §2.3）

- [ ] **Step 5: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass

- [ ] **Step 6: コミット**

```bash
git add tool/simulate_bonus.dart test/tool/simulate_bonus_test.dart docs/superpowers/specs/2026-09-05-bonus-gameover-and-effects-design.md
git commit -m "test(bonus): measure the capped game against the real Dart engine"
```

---

## 完了時の検証

- [ ] **1. テスト全体**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存 460 が 1 つも壊れていないこと。**

- [ ] **2. アナライザ（ASCII パスのコピーで）**

```bash
rm -rf /c/Temp/m10go && mkdir -p /c/Temp/m10go
cd "C:/Users/e-yak/OneDrive/ドキュメント/nanaumi/MAKE10" && git archive HEAD | tar -x -C /c/Temp/m10go
cd /c/Temp/m10go && C:/flutter/bin/flutter.bat pub get && C:/flutter/bin/flutter.bat analyze
```

Expected: `No issues found!`。終わったら `rm -rf /c/Temp/m10go`。

- [ ] **3. Web ビルド**

```bash
C:/flutter/bin/flutter.bat build web --no-tree-shake-icons; echo "exit=$?"
```

Expected: exit=0。**パイプに通さないこと。**

- [ ] **4. 広告・課金プラグインが混入していないこと**

```bash
grep -c "google_mobile_ads\|in_app_purchase" build/web/main.dart.js || echo "0 matches (expected)"
```

Expected: 0 matches

- [ ] **5. ブランチの状態**

```bash
git status --porcelain
git log --oneline main..feat/bonus-gameover
```

Expected: 作業ツリーがクリーン（`analysis_options.yaml` が SDK に
書き換えられていたら `git checkout -- analysis_options.yaml`）。
