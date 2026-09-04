# ボーナスゲーム 実装計画 (後半)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

[前半 (Task 1〜6)](2026-09-03-make10-bonus-game.md) の続き。**Global Constraints は前半のものがそのまま適用される。**

前半で作られたもの（後半のタスクが依存する API）:

```dart
// lib/domain/bonus/bonus_grid.dart
const int kBonusSize = 5;      // 盤面の一辺
const int kBonusCells = 25;    // 盤面のマス数
const int kBonusTarget = 10;   // 目標値
const int kBonusEmpty = 0;     // 空きマス

class BonusGrid {
  factory BonusGrid.of(List<int> cells);   // 長さ 25 以外は ArgumentError
  factory BonusGrid.deal(Random random);   // 初期盤面 (1..3 の混在)
  List<int> get cells;                     // unmodifiable, 長さ 25
  int valueAt(int row, int col);
  int get maxValue;
  Set<int> componentAt(int index);
  bool canTap(int index);
  bool get hasLegalMove;
  BonusMerge? tap(int index, Random random);   // 不正な手なら null
  BonusRepair repairIfStuck(Random random);
}

class BonusMerge {
  BonusGrid get grid;
  int get gained;        // mergedValue * mergedCount
  int get mergedValue;
  int get mergedCount;
  bool get cleared;
  int get repairedCells; // 詰み修復で書き換えたマス数。0 なら修復なし
}

class BonusRepair {
  BonusGrid get grid;
  int get changedCells;
}

// lib/domain/bonus_ticket.dart
const int kBonusUnlockClears = 5;
String bonusDateKey(DateTime local);   // 'yyyy-MM-dd'

class BonusTicket {
  BonusTicket({String? unlockedOn, String? playedOn});
  String? get unlockedOn;
  String? get playedOn;
  bool earn(String today);        // 新しく解禁したら true
  bool isAvailable(String today);
  void consume(String today);
}
```

---

### Task 7: 永続化

**Files:**
- Create: `lib/data/bonus_repository.dart`
- Test: `test/data/bonus_repository_test.dart`

**Interfaces:**
- Consumes: `BonusGrid`、`BonusTicket`、`bonusDateKey`
- Produces: `class BonusRepository extends ChangeNotifier` —
  - `Future<void> load()`
  - `int get bestScore`
  - `BonusTicket get ticket`
  - `BonusGrid? get inProgressGrid`
  - `int get inProgressScore`
  - `bool get hasInProgress`
  - `Future<bool> earn(String today)` — 新しく解禁したら true
  - `Future<void> startGame(String today, BonusGrid grid)` — 権利を消費して途中状態を書く
  - `Future<void> saveProgress(BonusGrid grid, int score)`
  - `Future<bool> finish(int score)` — 途中状態を消してベストを更新。更新したら true

- [ ] **Step 1: 失敗するテストを書く**

`test/data/bonus_repository_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid sampleGrid() => gridOf([
      [1, 1, 3, 1, 2],
      [3, 1, 2, 3, 1],
      [2, 3, 1, 2, 3],
      [1, 2, 3, 1, 2],
      [3, 1, 2, 3, 1],
    ]);

Future<BonusRepository> loaded() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('初期状態', () {
    test('何も保存されていなければ既定値', () async {
      final repo = await loaded();
      expect(repo.bestScore, 0);
      expect(repo.ticket.unlockedOn, isNull);
      expect(repo.ticket.playedOn, isNull);
      expect(repo.hasInProgress, isFalse);
      expect(repo.inProgressGrid, isNull);
      expect(repo.inProgressScore, 0);
    });
  });

  group('往復', () {
    test('解禁を保存して読み直せる', () async {
      final repo = await loaded();
      expect(await repo.earn('2026-09-03'), isTrue);

      final reloaded = await loaded();
      expect(reloaded.ticket.isAvailable('2026-09-03'), isTrue);
    });

    test('開始で権利を消費し、途中状態を保存する', () async {
      final repo = await loaded();
      await repo.earn('2026-09-03');
      await repo.startGame('2026-09-03', sampleGrid());

      final reloaded = await loaded();
      expect(reloaded.ticket.isAvailable('2026-09-03'), isFalse,
          reason: '開始時に権利が消費されていない');
      expect(reloaded.hasInProgress, isTrue);
      expect(reloaded.inProgressGrid!.cells, sampleGrid().cells);
      expect(reloaded.inProgressScore, 0);
    });

    test('途中のスコアと盤面を保存して読み直せる', () async {
      final repo = await loaded();
      await repo.earn('2026-09-03');
      await repo.startGame('2026-09-03', sampleGrid());
      final advanced = gridOf([
        [2, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
        [2, 3, 1, 2, 3],
        [1, 2, 3, 1, 2],
        [3, 1, 2, 3, 1],
      ]);
      await repo.saveProgress(advanced, 340);

      final reloaded = await loaded();
      expect(reloaded.inProgressGrid!.cells, advanced.cells);
      expect(reloaded.inProgressScore, 340);
    });

    test('終了で途中状態が消え、ベストが更新される', () async {
      final repo = await loaded();
      await repo.earn('2026-09-03');
      await repo.startGame('2026-09-03', sampleGrid());
      expect(await repo.finish(994), isTrue);

      final reloaded = await loaded();
      expect(reloaded.hasInProgress, isFalse);
      expect(reloaded.inProgressGrid, isNull);
      expect(reloaded.bestScore, 994);
    });

    test('ベストを下回るスコアでは更新しない', () async {
      final repo = await loaded();
      await repo.finish(994);
      expect(await repo.finish(500), isFalse);
      expect(repo.bestScore, 994);
    });

    test('同点では更新しない', () async {
      final repo = await loaded();
      await repo.finish(994);
      expect(await repo.finish(994), isFalse);
    });
  });

  group('通知', () {
    test('earn / startGame / finish で listener が呼ばれる', () async {
      final repo = await loaded();
      var calls = 0;
      repo.addListener(() => calls++);

      await repo.earn('2026-09-03');
      expect(calls, greaterThanOrEqualTo(1));

      final before = calls;
      await repo.startGame('2026-09-03', sampleGrid());
      expect(calls, greaterThan(before));

      final beforeFinish = calls;
      await repo.finish(100);
      expect(calls, greaterThan(beforeFinish));
    });
  });

  group('壊れたデータ', () {
    test('JSON として読めなければ既定値で続行する', () async {
      SharedPreferences.setMockInitialValues({'make10.bonus': 'not json'});
      final repo = await loaded();
      expect(repo.bestScore, 0);
      expect(repo.hasInProgress, isFalse);
    });

    test('型が違えば既定値で続行する', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'bestScore': 'たくさん',
          'unlockedOn': 42,
        }),
      });
      final repo = await loaded();
      expect(repo.bestScore, 0);
    });

    test('盤面が 25 マスでなければ途中状態を破棄する', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'bestScore': 500,
          'playedOn': '2026-09-03',
          'inProgress': {'grid': [1, 2, 3], 'score': 40},
        }),
      });
      final repo = await loaded();
      expect(repo.hasInProgress, isFalse,
          reason: '長さの合わない盤面が復元されている');
      // 途中状態だけを捨て、他のフィールドは活かす。
      expect(repo.bestScore, 500);
      expect(repo.ticket.playedOn, '2026-09-03');
    });

    test('盤面に範囲外の値が含まれれば途中状態を破棄する', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': [for (var i = 0; i < 25; i++) i == 3 ? 99 : 1],
            'score': 40,
          },
        }),
      });
      final repo = await loaded();
      expect(repo.hasInProgress, isFalse);
    });

    test('盤面に int でない要素が混ざっていても load を抜けない', () async {
      // cast<int>() は遅延評価なので、壊れた要素は load() の try/catch を
      // すり抜け、後から無関係な場所で TypeError として現れる。
      // List<int>.from(...) で読み込み時に確定させること。
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'bestScore': 700,
          'inProgress': {
            'grid': [for (var i = 0; i < 25; i++) i == 7 ? 'x' : 1],
            'score': 40,
          },
        }),
      });
      final repo = await loaded();
      expect(repo.hasInProgress, isFalse);
      expect(repo.bestScore, 700);
      // 破棄した後も盤面に触れても落ちない。
      expect(repo.inProgressGrid, isNull);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_repository_test.dart`
Expected: FAIL — `bonus_repository.dart` が存在しない

- [ ] **Step 3: 実装を書く**

`lib/data/bonus_repository.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/bonus/bonus_grid.dart';
import '../domain/bonus_ticket.dart';

const String _prefsKey = 'make10.bonus';

/// ボーナスゲームのベストスコア・1 日 1 回の権利・中断した盤面を
/// 端末内に保存する。
///
/// [ChangeNotifier] を継承しているのは、ホーム画面の入口が 4 状態
/// （未解禁 / 解禁済み / 本日終了 / 中断あり）を切り替える必要があり、
/// タイムアタックのリザルトで解禁した瞬間にもホームへ戻る前に追従させたい
/// ため（既存 [EntitlementRepository] と同じパターン）。Riverpod の
/// FutureProvider はインスタンスを 1 度だけ生成してキャッシュするので、
/// その後のフィールドの書き換えはプロバイダの再評価では検知できない。
class BonusRepository extends ChangeNotifier {
  int _bestScore = 0;
  BonusTicket _ticket = BonusTicket();
  BonusGrid? _inProgressGrid;
  int _inProgressScore = 0;

  int get bestScore => _bestScore;
  BonusTicket get ticket => _ticket;
  BonusGrid? get inProgressGrid => _inProgressGrid;
  int get inProgressScore => _inProgressScore;
  bool get hasInProgress => _inProgressGrid != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    var bestScore = 0;
    var ticket = BonusTicket();
    BonusGrid? grid;
    var score = 0;

    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        bestScore = data['bestScore'] as int? ?? 0;
        ticket = BonusTicket(
          unlockedOn: data['unlockedOn'] as String?,
          playedOn: data['playedOn'] as String?,
        );
        final inProgress = data['inProgress'];
        if (inProgress is Map<String, dynamic>) {
          // 途中状態だけが壊れている場合に、ベストスコアや権利まで
          // 巻き添えで失わないよう、ここは独立した try で囲む。
          try {
            grid = _decodeGrid(inProgress['grid']);
            score = inProgress['score'] as int? ?? 0;
          } catch (_) {
            grid = null;
            score = 0;
          }
        }
      } catch (_) {
        // 壊れていたら初期値で続行する。既存 StatsRepository.load と
        // 同じ方針で、プレイを妨げない。
        bestScore = 0;
        ticket = BonusTicket();
        grid = null;
        score = 0;
      }
    }

    _bestScore = bestScore;
    _ticket = ticket;
    _inProgressGrid = grid;
    _inProgressScore = score;
    notifyListeners();
  }

  /// 解禁条件を満たしたときに呼ぶ。新しく遊べるようになったら true。
  Future<bool> earn(String today) async {
    final unlocked = _ticket.earn(today);
    if (unlocked) {
      await _save();
      notifyListeners();
    }
    return unlocked;
  }

  /// ゲームを開始する。権利を消費し、初期盤面を途中状態として書く。
  ///
  /// 完了時ではなく開始時に消費するのが要点（仕様 §4.3）。強制終了で
  /// 無限にリトライできてしまうのを防ぐ。同時に盤面を保存することで、
  /// 中断しても再開できるようにして、開始時消費の実害を消している。
  Future<void> startGame(String today, BonusGrid grid) async {
    _ticket.consume(today);
    _inProgressGrid = grid;
    _inProgressScore = 0;
    await _save();
    notifyListeners();
  }

  Future<void> saveProgress(BonusGrid grid, int score) async {
    _inProgressGrid = grid;
    _inProgressScore = score;
    await _save();
    notifyListeners();
  }

  /// ゲームを終える。途中状態を消し、ベストを更新したら true。
  Future<bool> finish(int score) async {
    final improved = score > _bestScore;
    if (improved) _bestScore = score;
    _inProgressGrid = null;
    _inProgressScore = 0;
    await _save();
    notifyListeners();
    return improved;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final grid = _inProgressGrid;
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'version': 1,
        'bestScore': _bestScore,
        'unlockedOn': _ticket.unlockedOn,
        'playedOn': _ticket.playedOn,
        if (grid != null)
          'inProgress': {
            'grid': grid.cells,
            'score': _inProgressScore,
          },
      }),
    );
  }
}

/// 保存された盤面を復元する。復元できない形なら例外を投げる
/// （呼び出し側が途中状態だけを破棄する）。
///
/// **`List<int>.from(...)` を使うのが要点。** `cast<int>()` は遅延評価
/// なので、int でない要素が混ざっていても [BonusRepository.load] の
/// try/catch をすり抜け、後から盤面を読んだ無関係な場所で TypeError
/// として現れる。この不具合はこのプロジェクトで実際に踏んだ。
BonusGrid _decodeGrid(Object? raw) {
  if (raw is! List) throw const FormatException('grid が配列でない');
  final cells = List<int>.from(raw);
  if (cells.length != kBonusCells) {
    throw FormatException('grid の長さが $kBonusCells でない: ${cells.length}');
  }
  for (final v in cells) {
    if (v < 1 || v > kBonusTarget) {
      throw FormatException('grid に範囲外の値がある: $v');
    }
  }
  return BonusGrid.of(cells);
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_repository_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: 遅延 cast の検査が本当に効くことを確認する**

`_decodeGrid` の `List<int>.from(raw)` を一時的に `raw.cast<int>()` に変える。

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_repository_test.dart`
Expected: **FAIL** — 「int でない要素が混ざっていても load を抜けない」が落ちる（`hasInProgress` が true のまま、または後続の行で TypeError）

確認したら `List<int>.from(raw)` に**必ず戻す**。戻して再実行し PASS を確認。

- [ ] **Step 6: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 7: コミット**

```bash
git add lib/data/bonus_repository.dart test/data/bonus_repository_test.dart
git commit -m "feat(bonus): persist the best score, the daily ticket and the in-progress board"
```

---

### Task 8: セッション

**Files:**
- Create: `lib/game/bonus_session.dart`
- Test: `test/game/bonus_session_test.dart`

**Interfaces:**
- Consumes: `BonusGrid`、`BonusRepository`
- Produces: `class BonusSession extends ChangeNotifier` —
  - `BonusSession({required BonusRepository repository, required BonusGrid grid, required int score, Random? random})`
  - `BonusGrid get grid`、`int get score`、`bool get isCleared`、`bool get isOver`
  - `int get lastRepairedCells`
  - `bool get isSavingResult`、`bool get bestUpdated`、`int get bestScore`
  - `void tap(int index)`
  - `void giveUp()`

- [ ] **Step 1: 失敗するテストを書く**

`test/game/bonus_session_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/game/bonus_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// (0,0) と (0,1) が 9 で、1 手でクリアできる盤面。
BonusGrid nearlyClearedGrid() => gridOf([
      [9, 9, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
    ]);

/// (1,0)(1,1)(1,2) と (2,1)(2,2) の 2 が連結する盤面（5 マス）。
BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

Future<BonusRepository> loadedRepo() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

Future<void> settle(BonusSession session, {int maxTurns = 50}) async {
  for (var i = 0; i < maxTurns && session.isSavingResult; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  if (session.isSavingResult) {
    fail('isSavingResult が $maxTurns 回のループ後も true のままだった');
  }
}

BonusSession sessionWith(
  BonusRepository repo,
  BonusGrid grid, {
  int score = 0,
  int seed = 0,
}) =>
    BonusSession(
      repository: repo,
      grid: grid,
      score: score,
      random: Random(seed),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('タップ', () {
    test('スコアが n*k で増える', () async {
      final session = sessionWith(await loadedRepo(), fiveTwosGrid());
      session.tap(5); // 2 が 5 マス連結
      expect(session.score, 10);
    });

    test('不正な手ではスコアも盤面も変わらない', () async {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final session = sessionWith(await loadedRepo(), grid);
      final before = session.grid.cells.toList();
      session.tap(12);
      expect(session.score, 0);
      expect(session.grid.cells, before);
    });

    test('listener が呼ばれる', () async {
      final session = sessionWith(await loadedRepo(), fiveTwosGrid());
      var calls = 0;
      session.addListener(() => calls++);
      session.tap(5);
      expect(calls, greaterThanOrEqualTo(1));
    });

    test('不正な手では listener を呼ばない', () async {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      final session = sessionWith(await loadedRepo(), grid);
      var calls = 0;
      session.addListener(() => calls++);
      session.tap(12);
      expect(calls, 0, reason: '盤面が変わっていないのに再描画を促している');
    });

    test('詰みを修復したマス数が読める', () async {
      // 詰みは 8 タップに 1 回起きるので、UI が通知を出せるように
      // 直前の手で何マス書き換わったかを公開する。
      final session = sessionWith(await loadedRepo(), fiveTwosGrid());
      session.tap(5);
      expect(session.lastRepairedCells, greaterThanOrEqualTo(0));
    });
  });

  group('クリア', () {
    test('10 を作ると isCleared / isOver になる', () async {
      final session = sessionWith(await loadedRepo(), nearlyClearedGrid());
      session.tap(0);
      expect(session.isCleared, isTrue);
      expect(session.isOver, isTrue);
    });

    test('クリア後のタップは無視される', () async {
      final session = sessionWith(await loadedRepo(), nearlyClearedGrid());
      session.tap(0);
      final scoreAtClear = session.score;
      final cellsAtClear = session.grid.cells.toList();
      session.tap(5);
      expect(session.score, scoreAtClear);
      expect(session.grid.cells, cellsAtClear);
    });

    test('クリアで途中状態が消えてベストが入る', () async {
      final repo = await loadedRepo();
      await repo.earn('2026-09-03');
      await repo.startGame('2026-09-03', nearlyClearedGrid());
      final session = sessionWith(repo, nearlyClearedGrid());
      session.tap(0);
      await settle(session);
      expect(repo.hasInProgress, isFalse);
      expect(repo.bestScore, session.score);
      expect(session.bestUpdated, isTrue);
    });
  });

  group('やめる', () {
    test('giveUp でその時点のスコアが確定する', () async {
      final repo = await loadedRepo();
      await repo.earn('2026-09-03');
      await repo.startGame('2026-09-03', fiveTwosGrid());
      final session = sessionWith(repo, fiveTwosGrid());
      session.tap(5);
      session.giveUp();
      await settle(session);
      expect(session.isOver, isTrue);
      expect(session.isCleared, isFalse);
      expect(repo.bestScore, 10);
      expect(repo.hasInProgress, isFalse);
    });
  });

  group('再開', () {
    test('保存された盤面とスコアから再開できる', () async {
      final session =
          sessionWith(await loadedRepo(), fiveTwosGrid(), score: 340);
      expect(session.score, 340);
      session.tap(5);
      expect(session.score, 350);
    });
  });

  group('dispose ガード', () {
    test('二重 dispose で落ちない', () async {
      final session = sessionWith(await loadedRepo(), fiveTwosGrid());
      session.dispose();
      expect(session.dispose, returnsNormally);
    });

    test('dispose 後のタップで落ちない', () async {
      final session = sessionWith(await loadedRepo(), fiveTwosGrid());
      session.dispose();
      expect(() => session.tap(5), returnsNormally);
    });

    test('保存の完了が dispose の後に届いても落ちない', () async {
      final repo = await loadedRepo();
      final session = sessionWith(repo, nearlyClearedGrid());
      session.tap(0); // クリア → 非同期の保存が始まる
      session.dispose(); // 保存の完了より先に破棄する
      // 保存が確定するまでイベントループを回す。notifyListeners が
      // 破棄後に呼ばれれば例外になる。
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repo.bestScore, greaterThan(0), reason: '保存自体は完了すべき');
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/game/bonus_session_test.dart`
Expected: FAIL — `bonus_session.dart` が存在しない

- [ ] **Step 3: 実装を書く**

`lib/game/bonus_session.dart`:

```dart
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/bonus_repository.dart';
import '../domain/bonus/bonus_grid.dart';

/// ボーナスゲーム 1 回分。
///
/// 盤面のルールは [BonusGrid]（純粋・イミュータブル）にあり、ここは
/// 乱数・スコアの累積・永続化をつなぐだけに留める。
///
/// [TimeAttackSession] と同じ `_disposed` ガードを持つ。あちらでは
/// ガードが無いために 3 つのクラッシュ経路があった（dispose 後に届く
/// 非同期の保存完了、二重 dispose、破棄後のストレイなイベント）。
/// ここも結果の保存が非同期なので同じ形が必要になる。
class BonusSession extends ChangeNotifier {
  final BonusRepository repository;
  final Random _random;

  BonusGrid _grid;
  int _score;
  bool _cleared = false;
  bool _gaveUp = false;
  int _lastRepairedCells = 0;
  bool _isSavingResult = false;
  bool _bestUpdated = false;
  bool _disposed = false;

  /// [grid] と [score] は新規なら `BonusGrid.deal(...)` と 0、再開なら
  /// [BonusRepository] に保存されていた値を渡す。
  BonusSession({
    required this.repository,
    required BonusGrid grid,
    required int score,
    Random? random,
  })  : _grid = grid,
        _score = score,
        _random = random ?? Random();

  BonusGrid get grid => _grid;
  int get score => _score;
  bool get isCleared => _cleared;
  bool get isOver => _cleared || _gaveUp;

  /// 直前の手で詰みの修復が書き換えたマス数。0 なら修復していない。
  ///
  /// 詰みは 1 ゲームに 13 回、およそ 8 タップに 1 回起きる（仕様 §3.2）。
  /// 無言で盤面が書き換わると理不尽に見えるので、UI がこれを見て短い
  /// 通知を出す。
  int get lastRepairedCells => _lastRepairedCells;

  /// 結果の書き込みが確定するまで true。
  ///
  /// [ResultScreen] と同じ理由で必要。時間切れ（ここではクリア）の瞬間は
  /// 書き込みが未完了で [bestUpdated] が false のままなので、そのまま
  /// 描くと古いベストが一瞬出てから「ベスト更新!」に切り替わる。
  bool get isSavingResult => _isSavingResult;

  bool get bestUpdated => _bestUpdated;
  int get bestScore => repository.bestScore;

  void tap(int index) {
    if (_disposed || isOver) return;
    final merge = _grid.tap(index, _random);
    // 不正な手では盤面が変わらないので、再描画も促さない。
    if (merge == null) return;

    _grid = merge.grid;
    _score += merge.gained;
    _lastRepairedCells = merge.repairedCells;

    if (merge.cleared) {
      _cleared = true;
      _finish();
    } else {
      // 1 手ごとに保存する。所要 5 分前後のゲームで、電話や
      // バックグラウンド化による中断は普通に起きる（仕様 §4.3）。
      repository.saveProgress(_grid, _score).ignore();
    }
    notifyListeners();
  }

  /// 途中でやめる。その時点のスコアを確定させる。
  void giveUp() {
    if (_disposed || isOver) return;
    _gaveUp = true;
    _finish();
    notifyListeners();
  }

  void _finish() {
    // isOver は tap()/giveUp() の呼び出し中に同期で確定させる。画面遷移や
    // 入力ロックがこれを await 抜きで即座に見られる必要があるため、
    // 下の非同期の保存処理を待ってはいけない（TimeAttackSession._finish と
    // 同じ理由）。
    _isSavingResult = true;
    repository.finish(_score).then(
      (improved) {
        _isSavingResult = false;
        _bestUpdated = improved;
        if (_disposed) return;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        // 書き込みが失敗しても isSavingResult を true に固定したままに
        // しない。結果画面がベスト行を永久に伏せてしまう。
        _isSavingResult = false;
        if (_disposed) return;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/game/bonus_session_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 5: dispose ガードが本当に効くことを確認する**

`_finish` の `onError` と成功側にある `if (_disposed) return;` を両方一時的に消す。

Run: `C:/flutter/bin/flutter.bat test test/game/bonus_session_test.dart`
Expected: **FAIL** — 「保存の完了が dispose の後に届いても落ちない」が `A BonusSession was used after being disposed.` で落ちる

確認したら 2 行を**必ず戻す**。戻して再実行し PASS を確認。

- [ ] **Step 6: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 7: コミット**

```bash
git add lib/game/bonus_session.dart test/game/bonus_session_test.dart
git commit -m "feat(bonus): drive one bonus run, saving progress after every move"
```

---

### Task 9: プロバイダと盤面ウィジェット

**Files:**
- Modify: `lib/game/providers.dart`（`bonusRepositoryProvider` を追加）
- Create: `lib/ui/widgets/bonus_grid_view.dart`
- Test: `test/ui/widgets/bonus_grid_view_test.dart`

**Interfaces:**
- Consumes: `BonusGrid`、`BonusRepository`
- Produces:
  - `final bonusRepositoryProvider = FutureProvider<BonusRepository>(...)`
  - `class BonusGridView extends StatelessWidget` — `BonusGridView({required BonusGrid grid, required void Function(int index) onTapCell})`

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/widgets/bonus_grid_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid distinctGrid() => gridOf([
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 1],
      [2, 3, 4, 5, 6],
      [7, 8, 9, 1, 2],
      [3, 4, 5, 6, 7],
    ]);

Future<void> pumpGrid(
  WidgetTester tester,
  BonusGrid grid, {
  required void Function(int) onTapCell,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: BonusGridView(grid: grid, onTapCell: onTapCell)),
      ),
    ),
  );
}

void main() {
  testWidgets('25 マスすべてを描く', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {});
    // 値 9 は 2 箇所、値 1 は 3 箇所にある。総数で数える。
    expect(find.byType(BonusCellTile), findsNWidgets(kBonusCells));
  });

  testWidgets('マスの数字を表示する', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {});
    expect(find.text('7'), findsNWidgets(3));
    expect(find.text('8'), findsNWidgets(2));
  });

  testWidgets('タップした添字を通知する', (tester) async {
    final tapped = <int>[];
    await pumpGrid(tester, distinctGrid(), onTapCell: tapped.add);
    await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
    await tester.tap(find.byKey(const ValueKey('bonus-cell-24')));
    await tester.tap(find.byKey(const ValueKey('bonus-cell-12')));
    expect(tapped, [0, 24, 12]);
  });

  testWidgets('320pt 幅でも 25 マスすべてがタップできる', (tester) async {
    // 既存 GameScreen で、固定サイズのカードが狭い画面で 2 行に折り返し、
    // 4 枚目がヒットテストに反応しなくなった不具合と同じ罠を防ぐ。
    // Wrap は溢れてもエラーを出さないので、テストで押せることを直接見る。
    final tapped = <int>[];
    await pumpGrid(
      tester,
      distinctGrid(),
      onTapCell: tapped.add,
      size: const Size(320, 480),
    );
    expect(tester.takeException(), isNull);
    for (var i = 0; i < kBonusCells; i++) {
      await tester.tap(find.byKey(ValueKey('bonus-cell-$i')));
    }
    expect(tapped, [for (var i = 0; i < kBonusCells; i++) i],
        reason: '320pt 幅で押せないマスがある');
  });

  testWidgets('盤面は正方形で、横に溢れない', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {},
        size: const Size(320, 480));
    final box = tester.getSize(find.byType(BonusGridView));
    expect(box.width, closeTo(box.height, 1.0), reason: '盤面が正方形でない');
    expect(box.width, lessThanOrEqualTo(320));
  });

  testWidgets('横長の画面でも高さに収まる', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {},
        size: const Size(800, 360));
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byType(BonusGridView));
    expect(box.height, lessThanOrEqualTo(360));
  });

  testWidgets('10 のマスが他と区別して描かれる', (tester) async {
    final cleared = gridOf([
      [kBonusTarget, 1, 2, 3, 4],
      [5, 6, 7, 8, 9],
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 1],
      [2, 3, 4, 5, 6],
    ]);
    await pumpGrid(tester, cleared, onTapCell: (_) {});
    expect(find.text('10'), findsOneWidget);
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/widgets/bonus_grid_view_test.dart`
Expected: FAIL — `bonus_grid_view.dart` が存在しない

- [ ] **Step 3: `lib/ui/widgets/bonus_grid_view.dart` を書く**

```dart
import 'package:flutter/material.dart';

import '../../domain/bonus/bonus_grid.dart';

/// 5×5 の盤面。
///
/// **一辺は必ず実際の制約から計算する。** マスの寸法を固定値で組むと
/// 狭い画面（320pt 幅）で溢れ、しかも Wrap のような溢れても黙る配置では
/// テストにも引っかからない。既存 GameScreen で、固定サイズのカードが
/// 2 行に折り返して 4 枚目が押せなくなった不具合がそれだった。
///
/// ここでは [LayoutBuilder] で得た制約の短辺から一辺を決め、[Column] と
/// [Row] で組む。計算を誤れば溢れて RenderFlex のエラーになる — 黙って
/// 壊れるより、はっきり落ちる方を選ぶ。
class BonusGridView extends StatelessWidget {
  final BonusGrid grid;
  final void Function(int index) onTapCell;

  const BonusGridView({
    super.key,
    required this.grid,
    required this.onTapCell,
  });

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

        return SizedBox(
          width: side,
          height: side,
          child: Column(
            children: [
              for (var row = 0; row < kBonusSize; row++)
                Row(
                  children: [
                    for (var col = 0; col < kBonusSize; col++)
                      BonusCellTile(
                        key: ValueKey('bonus-cell-${row * kBonusSize + col}'),
                        value: grid.valueAt(row, col),
                        size: cell,
                        onTap: () => onTapCell(row * kBonusSize + col),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 盤面の 1 マス。
class BonusCellTile extends StatelessWidget {
  final int value;
  final double size;
  final VoidCallback onTap;

  const BonusCellTile({
    super.key,
    required this.value,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 値そのものを色相に写す。プレイヤーは数字を読む前に色で同値の塊を
    // 見つけるので、隣接する値（n と n+1）がはっきり違う色になることが
    // 要点。彩度と明度を固定して、10 段階を等間隔の色相に並べる。
    final isTarget = value >= kBonusTarget;
    final hue = (value - 1) * 34.0;
    final fill = isTarget
        ? scheme.primary
        : HSLColor.fromAHSL(1.0, hue % 360, 0.62, 0.55).toColor();

    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(size * 0.04),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(size * 0.14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(size * 0.14),
            child: Center(
              child: Text(
                '$value',
                style: TextStyle(
                  // マスの寸法から導く。固定値だと 320pt 幅で文字が
                  // マスに収まらない。
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.bold,
                  color: isTarget ? scheme.onPrimary : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `lib/game/providers.dart` にプロバイダを追加**

import を追加:

```dart
import '../data/bonus_repository.dart';
```

ファイル末尾に追加:

```dart
/// ボーナスゲームのベストスコア・1 日 1 回の権利・中断した盤面。
///
/// [ChangeNotifier] なので、ホーム画面の入口とタイムアタックのリザルトは
/// このインスタンス自身を [AnimatedBuilder] で購読する（プロバイダの
/// 再評価では状態変化を検知できない — entitlementRepositoryProvider と
/// 同じ理由）。
final bonusRepositoryProvider = FutureProvider<BonusRepository>((ref) async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
});
```

- [ ] **Step 5: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/widgets/bonus_grid_view_test.dart`
Expected: PASS（このファイルの全テスト）

- [ ] **Step 6: 320pt の検査が本当に効くことを確認する**

`BonusGridView` の `final cell = side / kBonusSize;` を一時的に
`const cell = 88.0;`（固定値）に変える。

Run: `C:/flutter/bin/flutter.bat test test/ui/widgets/bonus_grid_view_test.dart`
Expected: **FAIL** — 「320pt 幅でも 25 マスすべてがタップできる」または「盤面は正方形で、横に溢れない」が落ちる（`A RenderFlex overflowed by ... pixels` を伴う）

確認したら**必ず元に戻す**。戻して再実行し PASS を確認。

- [ ] **Step 7: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass。**既存の 319 テストが 1 つも壊れていないこと**と、このタスクで追加したテストが全部数えられていることを確認する（総数の絶対値は事前に数えても当てにならないので、`--reporter compact` の最終行で increase を見る）

- [ ] **Step 8: コミット**

```bash
git add lib/ui/widgets/bonus_grid_view.dart lib/game/providers.dart test/ui/widgets/bonus_grid_view_test.dart
git commit -m "feat(bonus): render the 5x5 board, sizing every cell from real constraints"
```

---

## 残りのタスク

Task 10 以降は [part3](2026-09-03-make10-bonus-game-part3.md) に続く。

- Task 10: `BonusGameScreen` / `BonusResultScreen`
- Task 11: ホーム画面の 4 状態
- Task 12: タイムアタックのリザルトでの解禁と `earn` の配線
- Task 13: 統計画面へのベストスコア追加
- Task 14: `tool/simulate_bonus.dart` で仕様 §3.1 の実測値を実エンジンで再現
