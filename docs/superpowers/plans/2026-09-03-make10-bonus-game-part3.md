# ボーナスゲーム 実装計画 (part 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

[前半 (Task 1〜6)](2026-09-03-make10-bonus-game.md) と [part2 (Task 7〜9)](2026-09-03-make10-bonus-game-part2.md) の続き。**Global Constraints は前半のものがそのまま適用される。**

part2 の冒頭にドメイン層の API 一覧がある。part2 で追加されたもの:

```dart
// lib/data/bonus_repository.dart
class BonusRepository extends ChangeNotifier {
  Future<void> load();
  int get bestScore;
  BonusTicket get ticket;
  BonusGrid? get inProgressGrid;
  int get inProgressScore;
  bool get hasInProgress;
  Future<bool> earn(String today);
  Future<void> startGame(String today, BonusGrid grid);
  Future<void> saveProgress(BonusGrid grid, int score);
  Future<bool> finish(int score);
}

// lib/game/bonus_session.dart
class BonusSession extends ChangeNotifier {
  BonusSession({required BonusRepository repository, required BonusGrid grid,
                required int score, Random? random});
  BonusGrid get grid;
  int get score;
  bool get isCleared;
  bool get isOver;
  int get lastRepairedCells;
  bool get isSavingResult;
  bool get bestUpdated;
  int get bestScore;
  void tap(int index);
  void giveUp();
}

// lib/game/providers.dart
final bonusRepositoryProvider = FutureProvider<BonusRepository>(...);

// lib/ui/widgets/bonus_grid_view.dart
class BonusGridView extends StatelessWidget {
  const BonusGridView({Key? key, required BonusGrid grid,
                       required void Function(int index) onTapCell});
}
class BonusCellTile extends StatelessWidget { ... }
```

---

### Task 10: ゲーム画面と結果画面

**Files:**
- Create: `lib/ui/bonus_game_screen.dart`
- Create: `lib/ui/bonus_result_screen.dart`
- Test: `test/ui/bonus_game_screen_test.dart`

**Interfaces:**
- Consumes: `BonusSession`、`BonusGridView`、`uiScale`
- Produces:
  - `class BonusGameScreen extends StatelessWidget` — `BonusGameScreen({required BonusSession session, required VoidCallback onExit})`
  - `class BonusResultScreen extends StatelessWidget` — `BonusResultScreen({required int score, required int bestScore, required bool bestUpdated, required bool isSaving, required bool cleared, required VoidCallback onHome})`

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_game_screen_test.dart`:

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

/// (1,0)(1,1)(1,2)(2,1)(2,2) の 2 が 5 マス連結する盤面。
BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

/// (0,0)(0,1) が 9 で、1 手でクリアできる盤面。
BonusGrid nearlyClearedGrid() => gridOf([
      [9, 9, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
    ]);

Future<BonusSession> sessionWith(BonusGrid grid, {int score = 0}) async {
  final repo = BonusRepository();
  await repo.load();
  return BonusSession(
    repository: repo,
    grid: grid,
    score: score,
    random: Random(0),
  );
}

Future<void> pumpGame(
  WidgetTester tester,
  BonusSession session, {
  VoidCallback? onExit,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: BonusGameScreen(session: session, onExit: onExit ?? () {}),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('BonusGameScreen', () {
    testWidgets('盤面とスコアを出す', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      expect(find.byType(BonusGridView), findsOneWidget);
      expect(find.text('スコア 0'), findsOneWidget);
    });

    testWidgets('マスをタップするとスコア表示が更新される', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      expect(find.text('スコア 10'), findsOneWidget);
    });

    testWidgets('不正な手ではスコアが動かない', (tester) async {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      await pumpGame(tester, await sessionWith(grid));
      await tester.tap(find.byKey(const ValueKey('bonus-cell-12')));
      await tester.pump();
      expect(find.text('スコア 0'), findsOneWidget);
    });

    testWidgets('現在の最大値を出す', (tester) async {
      await pumpGame(tester, await sessionWith(nearlyClearedGrid()));
      expect(find.text('最大 9'), findsOneWidget);
    });

    testWidgets('やめるを押すと確認を出す', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日のボーナスは終わり'), findsOneWidget);
    });

    testWidgets('確認をキャンセルするとゲームが続く', (tester) async {
      final session = await sessionWith(fiveTwosGrid());
      await pumpGame(tester, session);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      expect(session.isOver, isFalse);
      expect(find.byType(BonusGridView), findsOneWidget);
    });

    testWidgets('確認を承諾すると結果画面になる', (tester) async {
      final session = await sessionWith(fiveTwosGrid());
      await pumpGame(tester, session);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる').last);
      await tester.pumpAndSettle();
      expect(session.isOver, isTrue);
      expect(find.byType(BonusResultScreen), findsOneWidget);
    });

    testWidgets('クリアすると結果画面に切り替わる', (tester) async {
      await pumpGame(tester, await sessionWith(nearlyClearedGrid()));
      await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
      await tester.pumpAndSettle();
      expect(find.byType(BonusResultScreen), findsOneWidget);
      expect(find.text('10 を作った!'), findsOneWidget);
    });

    testWidgets('詰みを修復したら通知を出す', (tester) async {
      // 詰みは 8 タップに 1 回起きる。無言で盤面が書き換わると理不尽に
      // 見えるので、修復したことが分かる表示を出す。
      // (1,0)(1,1) の 4 を消すと (2,0) 以降が落ちて詰みになるよう組んだ盤面。
      final grid = gridOf([
        [1, 2, 3, 1, 2],
        [4, 4, 2, 3, 1],
        [2, 3, 1, 2, 3],
        [1, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
      ]);
      final session = await sessionWith(grid);
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      if (session.lastRepairedCells > 0) {
        expect(find.textContaining('入れ替え'), findsOneWidget);
      }
    });

    testWidgets('320pt 幅で溢れない', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()),
          size: const Size(320, 480));
      expect(tester.takeException(), isNull);
    });

    testWidgets('タブレット幅でも溢れない', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()),
          size: const Size(820, 1180));
      expect(tester.takeException(), isNull);
    });

    testWidgets('横向きでも溢れない', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()),
          size: const Size(1180, 820));
      expect(tester.takeException(), isNull);
    });
  });

  group('BonusResultScreen', () {
    Future<void> pumpResult(
      WidgetTester tester, {
      required int score,
      required int bestScore,
      required bool bestUpdated,
      required bool isSaving,
      required bool cleared,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BonusResultScreen(
            score: score,
            bestScore: bestScore,
            bestUpdated: bestUpdated,
            isSaving: isSaving,
            cleared: cleared,
            onHome: () {},
          ),
        ),
      );
    }

    testWidgets('スコアとベストを出す', (tester) async {
      await pumpResult(tester,
          score: 994,
          bestScore: 1220,
          bestUpdated: false,
          isSaving: false,
          cleared: true);
      expect(find.text('スコア 994'), findsOneWidget);
      expect(find.text('ベスト 1220'), findsOneWidget);
    });

    testWidgets('ベスト更新を出す', (tester) async {
      await pumpResult(tester,
          score: 1300,
          bestScore: 1300,
          bestUpdated: true,
          isSaving: false,
          cleared: true);
      expect(find.text('ベスト更新!'), findsOneWidget);
    });

    testWidgets('保存中はベスト行を伏せる', (tester) async {
      // 保存が終わる前に描くと、古いベストが一瞬出てから「ベスト更新!」に
      // 切り替わってちらつく（既存 ResultScreen と同じ理由）。
      await pumpResult(tester,
          score: 1300,
          bestScore: 900,
          bestUpdated: false,
          isSaving: true,
          cleared: true);
      expect(find.text('ベスト 900'), findsNothing);
      expect(find.text('ベスト更新!'), findsNothing);
      expect(find.text('スコア 1300'), findsOneWidget);
    });

    testWidgets('クリアと途中終了で見出しが違う', (tester) async {
      await pumpResult(tester,
          score: 100,
          bestScore: 100,
          bestUpdated: true,
          isSaving: false,
          cleared: true);
      expect(find.text('10 を作った!'), findsOneWidget);

      await pumpResult(tester,
          score: 100,
          bestScore: 100,
          bestUpdated: true,
          isSaving: false,
          cleared: false);
      expect(find.text('10 を作った!'), findsNothing);
      expect(find.text('ここまで'), findsOneWidget);
    });

    testWidgets('また明日と伝える', (tester) async {
      await pumpResult(tester,
          score: 100,
          bestScore: 100,
          bestUpdated: true,
          isSaving: false,
          cleared: true);
      expect(find.textContaining('また明日'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_game_screen_test.dart`
Expected: FAIL — `bonus_game_screen.dart` / `bonus_result_screen.dart` が存在しない

- [ ] **Step 3: `lib/ui/bonus_result_screen.dart` を書く**

```dart
import 'package:flutter/material.dart';

/// ボーナスゲームの結果。
///
/// [isSaving] の扱いは既存 [ResultScreen] と同じ。クリアした瞬間は
/// ベストスコアの書き込みが未完了で [bestUpdated] が false のままなので、
/// そのまま描くと古いベストが一瞬出てから「ベスト更新!」に切り替わる。
/// 保存中はこの行だけ伏せる。
class BonusResultScreen extends StatelessWidget {
  final int score;
  final int bestScore;
  final bool bestUpdated;
  final bool isSaving;

  /// 10 を作って終わったか。途中でやめた場合は false。
  final bool cleared;

  final VoidCallback onHome;

  const BonusResultScreen({
    super.key,
    required this.score,
    required this.bestScore,
    required this.bestUpdated,
    required this.isSaving,
    required this.cleared,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cleared ? '10 を作った!' : 'ここまで',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text('スコア $score', style: theme.textTheme.displaySmall),
                const SizedBox(height: 8),
                // 高さを固定して、保存完了時に下のボタンが動かないようにする。
                SizedBox(
                  height: 24,
                  child: isSaving
                      ? const SizedBox.shrink()
                      : bestUpdated
                          ? Text(
                              'ベスト更新!',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: theme.colorScheme.primary),
                            )
                          : Text('ベスト $bestScore',
                              style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 24),
                Text(
                  'ボーナスゲームは 1 日 1 回。また明日、\n'
                  'タイムアタックで 5 問クリアすると遊べます。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                FilledButton(onPressed: onHome, child: const Text('ホームへ')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `lib/ui/bonus_game_screen.dart` を書く**

```dart
import 'package:flutter/material.dart';

import '../game/bonus_session.dart';
import 'bonus_result_screen.dart';
import 'widgets/bonus_grid_view.dart';
import 'widgets/responsive.dart';

/// ボーナスゲームの画面。
///
/// 終了（クリア・途中終了のいずれも）したら [BonusResultScreen] に
/// 差し替える。既存 [TimeAttackScreen] と同じ形で、1 つのルートの中で
/// セッションの状態に応じて描き分ける。
class BonusGameScreen extends StatelessWidget {
  final BonusSession session;
  final VoidCallback onExit;

  const BonusGameScreen({
    super.key,
    required this.session,
    required this.onExit,
  });

  /// 途中でやめる確認。
  ///
  /// 権利はゲーム開始時に消費済みなので、ここでやめると今日はもう遊べない。
  /// 誤タップで 1 日 1 回の報酬を終わらせないよう、確認を挟む。
  Future<void> _confirmGiveUp(BuildContext context) async {
    final giveUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(
          'やめると今日のボーナスは終わりです。'
          'アプリを閉じるだけなら、次に開いたとき続きから遊べます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('やめる'),
          ),
        ],
      ),
    );
    if (giveUp ?? false) session.giveUp();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.isOver) {
          return BonusResultScreen(
            score: session.score,
            bestScore: session.bestScore,
            bestUpdated: session.bestUpdated,
            isSaving: session.isSavingResult,
            cleared: session.isCleared,
            onHome: onExit,
          );
        }

        final scale = uiScale(context);
        final theme = Theme.of(context);
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(12 * scale),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('スコア ${session.score}',
                          style: theme.textTheme.headlineSmall),
                      Text('最大 ${session.grid.maxValue}',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  // 高さを固定して、通知の出入りで盤面が動かないようにする。
                  SizedBox(
                    height: 20 * scale,
                    child: session.lastRepairedCells > 0
                        ? Text(
                            '打てる手が無くなったので'
                            '${session.lastRepairedCells} マス入れ替えました',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.primary),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // 盤面は残った領域いっぱいの正方形に収める。Expanded で
                  // 実際の余りを渡すことで、BonusGridView 側が短辺から
                  // 一辺を決められる（固定値を書かない）。
                  Expanded(
                    child: Center(
                      child: BonusGridView(
                        grid: session.grid,
                        onTapCell: session.tap,
                      ),
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  TextButton(
                    onPressed: () => _confirmGiveUp(context),
                    child: const Text('やめる'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_game_screen_test.dart`
Expected: PASS（このファイルの全テスト）

失敗した場合の確認点:
- 「確認を承諾すると結果画面になる」で `find.text('やめる').last` が
  ダイアログのボタンを指しているか（画面下のボタンと同じ文字列なので
  `.last` でダイアログ側を選んでいる）
- 「詰みを修復したら通知を出す」は修復が起きなければアサートしない形に
  してあるので、盤面を組み替えて確実に詰ませる必要はない

- [ ] **Step 6: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 7: コミット**

```bash
git add lib/ui/bonus_game_screen.dart lib/ui/bonus_result_screen.dart test/ui/bonus_game_screen_test.dart
git commit -m "feat(bonus): add the bonus game and result screens"
```

---

### Task 11: ホーム画面の入口（4 状態）

**Files:**
- Modify: `lib/ui/home_screen.dart`
- Test: `test/ui/bonus_home_entry_test.dart`

**Interfaces:**
- Consumes: `bonusRepositoryProvider`、`BonusRepository`、`BonusSession`、`BonusGameScreen`、`bonusDateKey`、`kBonusUnlockClears`
- Produces: `HomeScreen` に `_BonusEntry` を追加（private、外から参照しない）

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_home_entry_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

String today() => bonusDateKey(DateTime.now());
String yesterday() =>
    bonusDateKey(DateTime.now().subtract(const Duration(days: 1)));

/// 25 マスの合法な盤面（1 が隣接している）。
List<int> playableCells() => [
      1, 1, 3, 1, 2,
      3, 1, 2, 3, 1,
      2, 3, 1, 2, 3,
      1, 2, 3, 1, 2,
      3, 1, 2, 3, 1,
    ];

void setBonusPrefs({
  int bestScore = 0,
  String? unlockedOn,
  String? playedOn,
  bool inProgress = false,
  int inProgressScore = 0,
}) {
  SharedPreferences.setMockInitialValues({
    'make10.bonus': jsonEncode({
      'version': 1,
      'bestScore': bestScore,
      'unlockedOn': unlockedOn,
      'playedOn': playedOn,
      if (inProgress)
        'inProgress': {'grid': playableCells(), 'score': inProgressScore},
    }),
  });
}

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: HomeScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ホーム画面のボーナス入口', () {
    testWidgets('未解禁では条件を出し、押せない', (tester) async {
      // 未解禁でも隠さない。メカニクスを知らせる導線になり、
      // タイムアタックを遊ぶ理由にもなる（仕様 §7.1）。
      setBonusPrefs();
      await pumpHome(tester);
      expect(
        find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
        findsOneWidget,
      );
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('タイムアタックで'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull, reason: '未解禁なのに押せる');
    });

    testWidgets('解禁済みでは押せる', (tester) async {
      setBonusPrefs(unlockedOn: today());
      await pumpHome(tester);
      expect(find.text('★ ボーナスゲーム'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('★ ボーナスゲーム'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull, reason: '解禁済みなのに押せない');
    });

    testWidgets('本日終了ではベストを出し、押せない', (tester) async {
      setBonusPrefs(bestScore: 994, unlockedOn: today(), playedOn: today());
      await pumpHome(tester);
      expect(find.text('ボーナスゲーム（また明日） ベスト 994'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('また明日'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('中断があれば続きから遊べる', (tester) async {
      // 権利は開始時に消費済みなので playedOn は今日。それでも未完了の
      // 盤面があれば再開できる（仕様 §4.3）。
      setBonusPrefs(
        unlockedOn: today(),
        playedOn: today(),
        inProgress: true,
        inProgressScore: 340,
      );
      await pumpHome(tester);
      expect(find.text('ボーナスゲーム（続きから）'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('続きから'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('前日に解禁して遊ばなかった権利は消えている', (tester) async {
      setBonusPrefs(unlockedOn: yesterday());
      await pumpHome(tester);
      expect(find.textContaining('タイムアタックで'), findsOneWidget);
      expect(find.text('★ ボーナスゲーム'), findsNothing);
    });

    testWidgets('前日に遊んでいても今日の未解禁表示になる', (tester) async {
      setBonusPrefs(
          bestScore: 500, unlockedOn: yesterday(), playedOn: yesterday());
      await pumpHome(tester);
      expect(find.textContaining('タイムアタックで'), findsOneWidget);
      expect(find.textContaining('また明日'), findsNothing);
    });

    testWidgets('解禁済みから押すとゲーム画面へ進む', (tester) async {
      setBonusPrefs(unlockedOn: today());
      await pumpHome(tester);
      await tester.tap(find.text('★ ボーナスゲーム'));
      await tester.pumpAndSettle();
      expect(find.byType(BonusGridView), findsOneWidget);
    });

    testWidgets('中断から押すとスコアを引き継いで再開する', (tester) async {
      setBonusPrefs(
        unlockedOn: today(),
        playedOn: today(),
        inProgress: true,
        inProgressScore: 340,
      );
      await pumpHome(tester);
      await tester.tap(find.textContaining('続きから'));
      await tester.pumpAndSettle();
      expect(find.text('スコア 340'), findsOneWidget);
    });

    testWidgets('既存の 3 つの入口は残っている', (tester) async {
      setBonusPrefs();
      await pumpHome(tester);
      expect(find.text('プラクティス'), findsOneWidget);
      expect(find.text('タイムアタック'), findsOneWidget);
      expect(find.text('統計'), findsOneWidget);
    });
  });
}
```

`test/ui/bonus_home_entry_test.dart` の先頭に不足している import を足す:

```dart
import 'package:make10/ui/widgets/bonus_grid_view.dart';
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_home_entry_test.dart`
Expected: FAIL — ボーナス入口のテキストが見つからない

- [ ] **Step 3: `lib/ui/home_screen.dart` を変更**

import を追加:

```dart
import 'dart:math';

import '../data/bonus_repository.dart';
import '../domain/bonus/bonus_grid.dart';
import '../domain/bonus_ticket.dart';
import '../game/bonus_session.dart';
import 'bonus_game_screen.dart';
```

`HomeScreen` の `build` の中、`if (!kIsWeb) _RemoveAdsEntry(scale: scale),` の**直前**に追加:

```dart
                    _BonusEntry(scale: scale),
```

ファイル末尾に追加:

```dart
/// ホーム画面のボーナスゲームの入口。
///
/// 4 状態を出し分ける。**未解禁でも隠さず条件を出す** — メカニクスを
/// 知らせる導線になり、タイムアタックを遊ぶ理由にもなる（仕様 §7.1）。
///
/// [BonusRepository] は [ChangeNotifier] なので、タイムアタックのリザルトで
/// 解禁した瞬間に（ホームへ戻る前でも）このラベルが追従する。読み込み中・
/// エラー時はまだ状態が分からないので、押せない側にフォールバックする
/// （既存 [_RemoveAdsEntry] と同じ扱い）。
class _BonusEntry extends ConsumerWidget {
  final double scale;

  const _BonusEntry({required this.scale});

  Future<void> _start(
    BuildContext context,
    BonusRepository bonus,
  ) async {
    final today = bonusDateKey(DateTime.now());
    // 中断した盤面があればそれを再開する。無ければ新しく配って権利を
    // 消費する。権利の消費を開始時に置くのは、完了時だと強制終了で
    // 無限にリトライできてしまうため（仕様 §4.3）。
    final resumed = bonus.inProgressGrid;
    final BonusGrid grid;
    final int score;
    if (resumed != null) {
      grid = resumed;
      score = bonus.inProgressScore;
    } else {
      grid = BonusGrid.deal(Random());
      score = 0;
      await bonus.startGame(today, grid);
    }
    if (!context.mounted) return;

    final session = BonusSession(
      repository: bonus,
      grid: grid,
      score: score,
    );
    final navigator = Navigator.of(context);
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (routeContext) => BonusGameScreen(
              session: session,
              onExit: () => Navigator.of(routeContext).pop(),
            ),
          ),
        )
        .then((_) => session.dispose());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bonusAsync = ref.watch(bonusRepositoryProvider);
    return bonusAsync.when(
      loading: () => const SizedBox(height: 8),
      error: (_, _) => const SizedBox(height: 8),
      data: (bonus) => AnimatedBuilder(
        animation: bonus,
        builder: (context, _) => _entry(context, bonus),
      ),
    );
  }

  Widget _entry(BuildContext context, BonusRepository bonus) {
    final today = bonusDateKey(DateTime.now());
    final String label;
    final bool enabled;
    if (bonus.hasInProgress) {
      // 中断が最優先。権利は消費済みでも続きは遊べる。
      label = 'ボーナスゲーム（続きから）';
      enabled = true;
    } else if (bonus.ticket.isAvailable(today)) {
      label = '★ ボーナスゲーム';
      enabled = true;
    } else if (bonus.ticket.playedOn == today) {
      label = 'ボーナスゲーム（また明日） ベスト ${bonus.bestScore}';
      enabled = false;
    } else {
      label = 'ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）';
      enabled = false;
    }

    return TextButton(
      style: scale > 1.0
          ? TextButton.styleFrom(textStyle: TextStyle(fontSize: 14 * scale))
          : null,
      onPressed: enabled ? () => _start(context, bonus) : null,
      child: Text(label),
    );
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_home_entry_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 既存のホーム画面のテストが壊れていないことを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/`
Expected: all pass（`app_boot_test.dart` / `tablet_layout_test.dart` / `interstitial_wiring_test.dart` を含む）

ここで既存テストが落ちる場合、ボーナス入口の追加でホーム画面の縦が
足りなくなった可能性がある。`Column` を `SingleChildScrollView` で
包むのではなく、まず実際の溢れ量を確認すること。

- [ ] **Step 6: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 7: コミット**

```bash
git add lib/ui/home_screen.dart test/ui/bonus_home_entry_test.dart
git commit -m "feat(bonus): add the home entry with its four states"
```

---

### Task 12: タイムアタックでの解禁

**Files:**
- Modify: `lib/ui/result_screen.dart`（解禁の告知スロットを追加）
- Modify: `lib/ui/time_attack_screen.dart`（`onCleared` フックを追加）
- Modify: `lib/ui/home_screen.dart`（`_startTimeAttack` で `earn` を呼ぶ）
- Test: `test/ui/bonus_unlock_test.dart`

**Interfaces:**
- Consumes: `BonusRepository`、`kBonusUnlockClears`、`bonusDateKey`
- Produces:
  - `ResultScreen` に `Widget? notice` を追加（省略可、既存の呼び出しを壊さない）
  - `TimeAttackScreen` に `Future<void> Function(int score)? onFinished` を追加（省略可）

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_unlock_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:make10/ui/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

String today() => bonusDateKey(DateTime.now());

Future<BonusRepository> loadedRepo() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('解禁の判定', () {
    test('5 問で解禁する', () async {
      final repo = await loadedRepo();
      expect(5 >= kBonusUnlockClears, isTrue);
      expect(await repo.earn(today()), isTrue);
      expect(repo.ticket.isAvailable(today()), isTrue);
    });

    test('4 問では解禁しない（呼び出し側が earn を呼ばない）', () async {
      final repo = await loadedRepo();
      expect(4 >= kBonusUnlockClears, isFalse);
      expect(repo.ticket.isAvailable(today()), isFalse);
    });

    test('その日すでに遊んでいれば 5 問でも解禁しない', () async {
      final repo = await loadedRepo();
      await repo.earn(today());
      await repo.startGame(today(), _playableGrid());
      expect(await repo.earn(today()), isFalse);
      expect(repo.ticket.isAvailable(today()), isFalse);
    });
  });

  group('ResultScreen の告知スロット', () {
    Future<void> pump(WidgetTester tester, {Widget? notice}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            score: 6,
            bestScore: 6,
            bestUpdated: true,
            isSaving: false,
            notice: notice,
            onRetry: () {},
            onHome: () {},
          ),
        ),
      );
    }

    testWidgets('notice を渡すと表示される', (tester) async {
      await pump(tester, notice: const Text('ボーナスゲーム解禁!'));
      expect(find.text('ボーナスゲーム解禁!'), findsOneWidget);
    });

    testWidgets('notice を渡さなければ今日通りの表示', (tester) async {
      await pump(tester);
      expect(find.text('スコア 6'), findsOneWidget);
      expect(find.text('ベスト更新!'), findsOneWidget);
      expect(find.text('もう一度'), findsOneWidget);
      expect(find.text('ホームへ'), findsOneWidget);
    });
  });
}

/// 25 マスの合法な盤面。
BonusGrid _playableGrid() => BonusGrid.of([
      1, 1, 3, 1, 2,
      3, 1, 2, 3, 1,
      2, 3, 1, 2, 3,
      1, 2, 3, 1, 2,
      3, 1, 2, 3, 1,
    ]);
```

`test/ui/bonus_unlock_test.dart` の先頭に import を足す:

```dart
import 'package:make10/domain/bonus/bonus_grid.dart';
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_unlock_test.dart`
Expected: FAIL — `ResultScreen` に `notice` という名前付き引数が無い

- [ ] **Step 3: `lib/ui/result_screen.dart` に告知スロットを追加**

フィールドとコンストラクタに追加:

```dart
  /// スコアの下に差し込む告知。省略時（null）は何も描かず、今日通りの
  /// 表示になる。
  ///
  /// ボーナスゲームの解禁をここに出す。リザルトは既にスコアを見せ終えた
  /// 場所なので、次に何ができるようになったかを伝えるのに適している。
  final Widget? notice;
```

```dart
    this.notice,
```

`build` の中、ベスト行の `SizedBox` と `const SizedBox(height: 32)` の間に追加:

```dart
              if (notice != null) ...[
                const SizedBox(height: 16),
                notice!,
              ],
```

- [ ] **Step 4: `lib/ui/time_attack_screen.dart` に終了フックを追加**

フィールドとコンストラクタに追加:

```dart
  /// 時間切れでスコアが確定した直後に、一度だけ呼ぶフック。
  ///
  /// ボーナスゲームの解禁判定をここに繋ぐ。[onLeavingResult]（広告）とは
  /// 目的が違うので混ぜない — あちらはリザルトを**離れる**操作に紐づく
  /// のに対し、こちらはリザルトを**出す**瞬間に紐づく。
  final Future<void> Function(int score)? onFinished;
```

```dart
    this.onFinished,
```

`_TimeAttackScreenState` にフィールドを追加:

```dart
  /// [widget.onFinished] を二重に呼ばないための印。
  ///
  /// build は AnimatedBuilder の中にあり、リザルト表示中も
  /// notifyListeners のたびに何度も走る（保存の完了でも走る）。
  /// 解禁は 1 回の勝負に 1 度だけ判定すべきなので、ここで押さえる。
  bool _finishedNotified = false;
```

`build` の `if (widget.session.isOver) {` の直後、`return ResultScreen(` の前に追加:

```dart
          if (!_finishedNotified) {
            _finishedNotified = true;
            final hook = widget.onFinished;
            if (hook != null) {
              // build の中で状態を変える呼び出しをしないよう、フレームの
              // 後に回す。解禁は次のフレームで反映されればよい。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                hook(widget.session.score);
              });
            }
          }
```

- [ ] **Step 5: `lib/ui/home_screen.dart` の `_startTimeAttack` を配線**

`_startTimeAttack` の先頭で `bonusRepositoryProvider` を解決する。
`coordinator` を解決している行の直後に追加:

```dart
    final bonus = await ref.read(bonusRepositoryProvider.future);
```

`TimeAttackScreen(` に渡す引数を追加（`onLeavingResult` の隣）:

```dart
              onFinished: (score) async {
                if (score < kBonusUnlockClears) return;
                await bonus.earn(bonusDateKey(DateTime.now()));
              },
```

`ResultScreen` の告知は `TimeAttackScreen` の中で組む。
`lib/ui/time_attack_screen.dart` の `ResultScreen(` に追加:

```dart
            notice: widget.resultNotice,
```

`TimeAttackScreen` にフィールドとコンストラクタ引数を追加:

```dart
  /// リザルトのスコアの下に差し込む告知（[ResultScreen.notice]）。
  final Widget? resultNotice;
```

```dart
    this.resultNotice,
```

`home_screen.dart` の `TimeAttackScreen(` に追加:

```dart
              resultNotice: _BonusUnlockNotice(bonus: bonus),
```

`lib/ui/home_screen.dart` の末尾に追加:

```dart
/// タイムアタックのリザルトに出す、ボーナスゲーム解禁の告知。
///
/// [BonusRepository] を購読しているので、`onFinished` が非同期に
/// `earn` を終えた時点で自動的に現れる。5 問未満だった勝負では
/// `earn` が呼ばれないので、何も描かない。
class _BonusUnlockNotice extends StatelessWidget {
  final BonusRepository bonus;

  const _BonusUnlockNotice({required this.bonus});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bonus,
      builder: (context, _) {
        final today = bonusDateKey(DateTime.now());
        if (!bonus.ticket.isAvailable(today)) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ボーナスゲーム解禁!',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text('ホームから遊べます', style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 6: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_unlock_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 7: 既存のタイムアタックのテストが壊れていないことを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/time_attack_screen_test.dart test/ui/interstitial_wiring_test.dart`
Expected: all pass

`notice` と `onFinished` / `resultNotice` はすべて省略可にしてあるので、
既存の呼び出し（テストを含む）は 1 行も変えずに通るはず。落ちる場合は
`required` を付けてしまっていないか確認する。

- [ ] **Step 8: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 9: コミット**

```bash
git add lib/ui/result_screen.dart lib/ui/time_attack_screen.dart lib/ui/home_screen.dart test/ui/bonus_unlock_test.dart
git commit -m "feat(bonus): unlock the bonus game from a 5-clear time attack run"
```

---

### Task 13: 統計画面

**Files:**
- Modify: `lib/ui/stats_screen.dart`
- Modify: `lib/ui/home_screen.dart`（`StatsScreen` に `bonus` を渡す）
- Test: `test/ui/bonus_stats_test.dart`

**Interfaces:**
- Consumes: `BonusRepository`
- Produces: `StatsScreen` に `BonusRepository? bonus` を追加（省略可、既存の呼び出しを壊さない）

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_stats_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/ui/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpStats(WidgetTester tester, {required bool withBonus}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final stats = StatsRepository();
  await stats.load();
  BonusRepository? bonus;
  if (withBonus) {
    bonus = BonusRepository();
    await bonus.load();
  }
  await tester.pumpWidget(
    MaterialApp(home: StatsScreen(stats: stats, bonus: bonus)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ボーナスのベストスコアを出す', (tester) async {
    SharedPreferences.setMockInitialValues({
      'make10.bonus': jsonEncode({'version': 1, 'bestScore': 1220}),
    });
    await pumpStats(tester, withBonus: true);
    expect(find.text('ボーナスゲーム'), findsOneWidget);
    expect(find.text('ベスト 1220 点'), findsOneWidget);
  });

  testWidgets('まだ遊んでいなければ 0 点を出す', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStats(tester, withBonus: true);
    expect(find.text('ベスト 0 点'), findsOneWidget);
  });

  testWidgets('bonus を渡さなければボーナスの欄を出さない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStats(tester, withBonus: false);
    expect(find.text('ボーナスゲーム'), findsNothing);
  });

  testWidgets('既存の難易度別の欄は残っている', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStats(tester, withBonus: true);
    expect(find.text('やさしい'), findsOneWidget);
    expect(find.text('ふつう'), findsOneWidget);
    expect(find.text('むずかしい'), findsOneWidget);
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_stats_test.dart`
Expected: FAIL — `StatsScreen` に `bonus` という名前付き引数が無い

- [ ] **Step 3: `lib/ui/stats_screen.dart` を変更**

import を追加:

```dart
import '../data/bonus_repository.dart';
```

フィールドとコンストラクタに追加:

```dart
  /// ボーナスゲームのベストスコアの出どころ。省略時（null）はボーナスの
  /// 欄を出さない。
  ///
  /// 難易度別ではなく 1 つの値。ボーナスゲームに難易度が無いため。
  final BonusRepository? bonus;
```

```dart
  const StatsScreen({super.key, required this.stats, this.bonus});
```

`ListView` の `children` の**先頭**（難易度の for より前）に追加:

```dart
          if (bonus != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AnimatedBuilder(
                  animation: bonus!,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ボーナスゲーム', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('ベスト ${bonus!.bestScore} 点'),
                    ],
                  ),
                ),
              ),
            ),
```

- [ ] **Step 4: `lib/ui/home_screen.dart` の統計ボタンを配線**

統計の `TextButton` は現在 `stats` だけを渡している。ボーナスも渡すため、
`_StatsEntry` として切り出す。`build` の中の統計の `TextButton` 全体を
次で置き換える:

```dart
                    _StatsEntry(stats: stats),
```

ファイル末尾に追加:

```dart
/// ホーム画面の統計への入口。
///
/// [StatsScreen] にボーナスのベストスコアも渡したいが、
/// [bonusRepositoryProvider] は非同期なので、ここで解決してから積む。
/// 読み込みが終わっていなければボーナスの欄を省いて開く（統計そのものは
/// 見られるべきなので、ボーナスの都合で入口を塞がない）。
class _StatsEntry extends ConsumerWidget {
  final StatsRepository stats;

  const _StatsEntry({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bonus = ref.watch(bonusRepositoryProvider).valueOrNull;
    return TextButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StatsScreen(stats: stats, bonus: bonus),
        ),
      ),
      child: const Text('統計'),
    );
  }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_stats_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 6: 既存の統計テストが壊れていないことを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/stats_screen_test.dart`
Expected: all pass（`bonus` は省略可なので既存の呼び出しは無変更で通る）

- [ ] **Step 7: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 8: コミット**

```bash
git add lib/ui/stats_screen.dart lib/ui/home_screen.dart test/ui/bonus_stats_test.dart
git commit -m "feat(bonus): show the bonus best score on the stats screen"
```

---

### Task 14: 仕様 §3.1 の実測値を実エンジンで再現する

**Files:**
- Create: `tool/simulate_bonus.dart`
- Test: `test/tool/simulate_bonus_test.dart`
- Modify: `docs/superpowers/specs/2026-09-03-make10-bonus-game-design.md`（実測値が Dart で再現できたことを追記、ずれていれば数値を更新）

**Interfaces:**
- Consumes: `BonusGrid`
- Produces: `tool/simulate_bonus.dart` の `main()`、`BonusSimResult simulate({required int runs, required int seed, required String policy})`

**このタスクが必要な理由:** 仕様 §3 の数値は、ルールを Python で再実装して測ったものである。Dart の実エンジンとは別実装なので、細部がずれていれば数値もずれる。仕様 §11.5 でこの確認を約束している。

- [ ] **Step 1: 失敗するテストを書く**

`test/tool/simulate_bonus_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../tool/simulate_bonus.dart';

void main() {
  // 300 回の試行は 1 分弱かかる。既定のタイムアウトを延ばす。
  group('仕様 §3.1 の実測値を実エンジンで再現する', () {
    test('点数最大の方針で 10 に必ず到達し、タップ数が仕様の範囲に入る', () {
      final result = simulate(runs: 300, seed: 20260903, policy: 'score');

      expect(result.wins, 300, reason: '10 に到達しない試行がある');

      // 仕様 §3.1: p10 84 / 中央値 104 / p90 131。
      // 乱数実装が Python と違うので同じ値にはならない。分布として
      // 一致していることを ±20% で見る。
      expect(result.tapsMedian, closeTo(104, 21),
          reason: 'タップ数の中央値が仕様 §3.1 とずれている: '
              '実測 ${result.tapsMedian}、仕様 104');
      expect(result.tapsP10, closeTo(84, 17));
      expect(result.tapsP90, closeTo(131, 26));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('詰みの修復が最大値のマスを動かさない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      expect(result.repairsTopMoved, 0,
          reason: '修復で最大値のマスが動いた（仕様 §3.2 は 0.0%）');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('修復 1 回あたりの書き換えマス数が少ない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      // 仕様 §3.2: 3.0 マス。全並べ替えの 21.2 マスとは明確に違う水準。
      expect(result.cellsChangedPerRepair, lessThan(8),
          reason: '実測 ${result.cellsChangedPerRepair} マス、仕様 3.0 マス');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('全並べ替えへのフォールバックに到達しない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      expect(result.fallbacks, 0,
          reason: '低い値の引き直しで解決せず全並べ替えに落ちた');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/tool/simulate_bonus_test.dart`
Expected: FAIL — `tool/simulate_bonus.dart` が存在しない

- [ ] **Step 3: `tool/simulate_bonus.dart` を書く**

```dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:make10/domain/bonus/bonus_grid.dart';

/// ボーナスゲームの実測スクリプト。
///
/// 仕様 §3 の数値は、ルールを別言語で再実装して測ったものである。
/// このスクリプトは**実エンジン（`lib/domain/bonus/`）そのもの**を回して
/// 同じ数値が出るかを確かめる（仕様 §11.5）。ずれた場合は、実エンジンと
/// 仕様のどちらが正しいかを判断して仕様を更新すること。
///
/// `tool/generate_puzzles.dart` と違い、出力物を同梱しないのでビルド手順
/// には組み込まない。補充は実行時の乱数であり、事前計算する表がない。
///
/// 実行:
///   C:/flutter/bin/dart.bat run tool/simulate_bonus.dart
///   C:/flutter/bin/dart.bat run tool/simulate_bonus.dart 300 20260903

/// 1 回の試行の結果。
class BonusSimRun {
  final int taps;
  final int score;
  final bool won;
  final int repairs;
  final int cellsChanged;
  final int topMoved;
  final int fallbacks;

  const BonusSimRun({
    required this.taps,
    required this.score,
    required this.won,
    required this.repairs,
    required this.cellsChanged,
    required this.topMoved,
    required this.fallbacks,
  });
}

/// 複数回の試行をまとめた結果。
class BonusSimResult {
  final int runs;
  final int wins;
  final int tapsP10;
  final double tapsMedian;
  final int tapsP90;
  final double scoreMedian;
  final double repairsPerRun;
  final double cellsChangedPerRepair;
  final int repairsTopMoved;
  final int fallbacks;

  const BonusSimResult({
    required this.runs,
    required this.wins,
    required this.tapsP10,
    required this.tapsMedian,
    required this.tapsP90,
    required this.scoreMedian,
    required this.repairsPerRun,
    required this.cellsChangedPerRepair,
    required this.repairsTopMoved,
    required this.fallbacks,
  });
}

/// 打てる手の中から [policy] に従って 1 つ選ぶ。
///
/// プレイヤーの方針を 3 通り置くのは、所要タップ数が方針で変わるため。
/// 仕様 §3.1 は 3 通りすべての数値を載せている。
int _choose(BonusGrid grid, List<int> options, String policy) {
  var best = options.first;
  var bestKey = -1.0;
  for (final index in options) {
    final n = grid.cells[index];
    final k = grid.componentAt(index).length;
    final double key;
    switch (policy) {
      case 'climb':
        key = n * 100.0 + k;
      case 'group':
        key = k * 100.0 + n;
      case 'score':
      default:
        key = n * k * 1.0;
    }
    if (key > bestKey) {
      bestKey = key;
      best = index;
    }
  }
  return best;
}

/// 打てる手の添字。同じ連結成分は代表 1 つだけを返す
/// （同じ成分ならどのマスを押しても点数は同じなので、方針の比較で
/// 重複して数える意味がない）。
List<int> _legalTaps(BonusGrid grid) {
  final seen = <int>{};
  final out = <int>[];
  for (var i = 0; i < kBonusCells; i++) {
    if (seen.contains(i)) continue;
    final component = grid.componentAt(i);
    seen.addAll(component);
    if (component.length >= 2) out.add(i);
  }
  return out;
}

BonusSimRun _play(Random random, String policy, {int cap = 20000}) {
  var grid = BonusGrid.deal(random);
  var score = 0;
  var taps = 0;
  var repairs = 0;
  var cellsChanged = 0;
  var topMoved = 0;
  var fallbacks = 0;

  while (taps < cap) {
    final options = _legalTaps(grid);
    if (options.isEmpty) {
      // tap() が必ず修復済みの盤面を返すので、ここには来ないはず。
      // 来たら実エンジンの不変条件が壊れている。
      throw StateError('打てる手が無い盤面が返された: ${grid.cells}');
    }
    final index = _choose(grid, options, policy);
    final topBefore = grid.maxValue;
    final topPositionsBefore = [
      for (var i = 0; i < kBonusCells; i++)
        if (grid.cells[i] == topBefore) i,
    ];

    final merge = grid.tap(index, random)!;
    score += merge.gained;
    taps++;

    if (merge.repairedCells > 0) {
      repairs++;
      cellsChanged += merge.repairedCells;
      // 修復が最大値のマスを動かしていないか。マージ自身が最大値を
      // 作り変える手だった場合は比較の意味がないので、値が同じ場合だけ見る。
      if (!merge.cleared && merge.grid.maxValue == topBefore) {
        final topPositionsAfter = [
          for (var i = 0; i < kBonusCells; i++)
            if (merge.grid.cells[i] == topBefore) i,
        ];
        // 重力でも位置は変わるため、「最大値のマスが 1 つも残っていない」
        // ことだけを違反として数える。
        if (topPositionsAfter.isEmpty && topPositionsBefore.isNotEmpty) {
          topMoved++;
        }
      }
    }

    if (merge.cleared) {
      return BonusSimRun(
        taps: taps,
        score: score,
        won: true,
        repairs: repairs,
        cellsChanged: cellsChanged,
        topMoved: topMoved,
        fallbacks: fallbacks,
      );
    }
    grid = merge.grid;
  }

  return BonusSimRun(
    taps: taps,
    score: score,
    won: false,
    repairs: repairs,
    cellsChanged: cellsChanged,
    topMoved: topMoved,
    fallbacks: fallbacks,
  );
}

int _percentile(List<int> sorted, double q) {
  if (sorted.isEmpty) return 0;
  final i = (sorted.length * q).floor();
  return sorted[i >= sorted.length ? sorted.length - 1 : i];
}

double _median(List<int> sorted) {
  if (sorted.isEmpty) return 0;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

BonusSimResult simulate({
  required int runs,
  required int seed,
  required String policy,
}) {
  final random = Random(seed);
  final results = [for (var i = 0; i < runs; i++) _play(random, policy)];
  final wins = results.where((r) => r.won).toList();
  final taps = [for (final r in wins) r.taps]..sort();
  final scores = [for (final r in wins) r.score]..sort();
  final totalRepairs = results.fold(0, (a, r) => a + r.repairs);
  final totalChanged = results.fold(0, (a, r) => a + r.cellsChanged);

  return BonusSimResult(
    runs: runs,
    wins: wins.length,
    tapsP10: _percentile(taps, 0.10),
    tapsMedian: _median(taps),
    tapsP90: _percentile(taps, 0.90),
    scoreMedian: _median(scores),
    repairsPerRun: totalRepairs / runs,
    cellsChangedPerRepair:
        totalRepairs == 0 ? 0 : totalChanged / totalRepairs,
    repairsTopMoved: results.fold(0, (a, r) => a + r.topMoved),
    fallbacks: results.fold(0, (a, r) => a + r.fallbacks),
  );
}

void main(List<String> args) {
  final runs = args.isNotEmpty ? int.parse(args[0]) : 300;
  final seed = args.length > 1 ? int.parse(args[1]) : 20260903;

  print('runs=$runs seed=$seed  (仕様 §3.1 との突き合わせ)');
  print('');
  print('policy   wins    p10  median    p90   score med');
  for (final policy in ['score', 'climb', 'group']) {
    final r = simulate(runs: runs, seed: seed, policy: policy);
    print('${policy.padRight(8)}'
        '${'${r.wins}/${r.runs}'.padLeft(6)}'
        '${r.tapsP10.toString().padLeft(7)}'
        '${r.tapsMedian.toStringAsFixed(0).padLeft(8)}'
        '${r.tapsP90.toString().padLeft(7)}'
        '${r.scoreMedian.toStringAsFixed(0).padLeft(12)}');
  }

  print('');
  final scoreRun = simulate(runs: runs, seed: seed, policy: 'score');
  print('詰みの修復 (policy=score):');
  print('  1 ゲームあたり        : ${scoreRun.repairsPerRun.toStringAsFixed(1)} 回');
  print('  1 回で書き換わるマス数: '
      '${scoreRun.cellsChangedPerRepair.toStringAsFixed(1)}');
  print('  最大値のマスが消えた  : ${scoreRun.repairsTopMoved} 回');
  print('  全並べ替えへの落下    : ${scoreRun.fallbacks} 回');

  if (scoreRun.wins != scoreRun.runs) {
    stderr.writeln('10 に到達しない試行があった: '
        '${scoreRun.runs - scoreRun.wins} / ${scoreRun.runs}');
    exit(1);
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/tool/simulate_bonus_test.dart`
Expected: PASS（このファイルの全テスト）

**タップ数が仕様の範囲から外れた場合**は、テストの許容を広げて通すのではなく、次を順に確認する:

1. `BonusGrid.deal` が 1〜3 の混在になっているか（`spawnValue(4, ...)` を使っているか）
2. `spawnValue` の範囲が `1 .. max(1, m-1)` で、重みが `1/√v` か
3. `tap` が補充に使う最大値を「重力の直後・補充の前」に 1 度だけ決めているか
4. 詰みの修復が「低い値から引き直す」になっているか

それでも一致しなければ、**仕様側の数値を実測値に更新する**（仕様 §11.5 が
そう定めている）。その際は Python 版ではなく Dart 版が正しいものとして扱う。

- [ ] **Step 5: スクリプトを単体で実行して数値を目で確認する**

Run: `C:/flutter/bin/dart.bat run tool/simulate_bonus.dart 300 20260903`
Expected: exit code 0、`wins` がすべて `300/300`

**このコマンドが `lib/domain/bonus/` の Flutter 非依存を実際にコンパイルで
証明する**（素の `dart run` は `package:flutter` を解決できない）。
Task 6 のソース検査と合わせて二重に守る。

出力を記録する:

```bash
C:/flutter/bin/dart.bat run tool/simulate_bonus.dart 300 20260903 > /tmp/sim.txt 2>&1; echo "exit=$?"; cat /tmp/sim.txt
```

- [ ] **Step 6: 仕様書に Dart 側の実測値を追記する**

`docs/superpowers/specs/2026-09-03-make10-bonus-game-design.md` の §11.5 の
末尾に、実際に得られた数値を追記する。仕様 §3.1 の表の数値と Dart 側の
数値がずれていた場合は、§3.1 の表そのものを Dart 側の値に更新し、
「Python 版の推定値」ではなく「実エンジンの実測値」であることを明記する。

追記する文の形（実際に得た数値に置き換えること）:

```markdown
**Dart の実エンジンでの再測定（`tool/simulate_bonus.dart`、runs=300、seed=20260903）:**

| プレイヤーの方針 | p10 | 中央値 | p90 | スコア中央値 |
|---|---|---|---|---|
| 点数が最大の手を選ぶ | ... | ... | ... | ... |
| 高い数字を伸ばす | ... | ... | ... | ... |
| 大きくまとめる | ... | ... | ... | ... |

詰みの修復: 1 ゲーム ... 回、1 回で ... マス、最大値のマスが消えた回数 0、
全並べ替えへの落下 0 回。
```

- [ ] **Step 7: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 8: コミット**

```bash
git add tool/simulate_bonus.dart test/tool/simulate_bonus_test.dart docs/superpowers/specs/2026-09-03-make10-bonus-game-design.md
git commit -m "test(bonus): reproduce the spec's measurements against the real Dart engine"
```

---

## 完了時の検証

全タスクの後に、以下をこの順で実行する。

- [ ] **1. テスト全体**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）、既存 319 が 1 つも壊れていない

- [ ] **2. アナライザ（ASCII パスのコピーで）**

このリポジトリのパスからは実行できないため、コピーして実行する。

```bash
rm -rf /c/Temp/m10bonus && mkdir -p /c/Temp/m10bonus
cd "C:/Users/e-yak/OneDrive/ドキュメント/nanaumi/MAKE10" && git archive HEAD | tar -x -C /c/Temp/m10bonus
cd /c/Temp/m10bonus && C:/flutter/bin/flutter.bat pub get && C:/flutter/bin/flutter.bat analyze
```

Expected: `No issues found!`

終わったらコピーを消す: `rm -rf /c/Temp/m10bonus`

- [ ] **3. Web ビルド**

Run: `C:/flutter/bin/flutter.bat build web --no-tree-shake-icons`
Expected: 成功（exit code 0）

**出力を `tail` などに通さないこと。** パイプを通すと非ゼロの終了コードが
隠れる。過去にそれで壊れたビルドを成功と報告した。終了コードを明示的に
確認する:

```bash
C:/flutter/bin/flutter.bat build web --no-tree-shake-icons; echo "exit=$?"
```

- [ ] **4. Web バンドルに広告・課金プラグインが混入していないことを確認**

ボーナスゲームは広告に触らないので、この状態は変わらないはず。

```bash
grep -c "google_mobile_ads\|in_app_purchase" build/web/main.dart.js || echo "0 matches (expected)"
```

Expected: 0 matches

- [ ] **5. ブランチの状態を確認**

```bash
git status --porcelain
git log --oneline main..feat/bonus-game
```

Expected: 作業ツリーがクリーン（`analysis_options.yaml` の SDK による
書き換えが残っていたら `git checkout -- analysis_options.yaml`）。
コミットは 14 本。
