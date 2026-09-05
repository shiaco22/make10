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
      // 実測: このシードは 89 手目までに 3 回目の修復が起きる
      // (400 手の余裕を見ている)。
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
    // seed 9 は実測でゲームオーバーに終わることを確認済み(「最初にタップ
    // 可能なマス」戦略で 127 手目、repairsUsed=10 で詰む)。このグループの
    // 全テストで同じ seed 9 を使うのはそのため — cleared で終わる seed
    // だと、ここから下のテストは「ゲームオーバー」を名乗りながら
    // 実際には一度もその経路を通らずに通ってしまう。
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
      // seed 9 が実際にゲームオーバーで終わることを断定する。if で分岐
      // すると、万一いつか到達しなくなっても検査が空回りして気付けない。
      expect(s.isGameOver, isTrue,
          reason: 'seed 9 はゲームオーバーで終わる実測値のはず');
      expect(s.outcome, BonusOutcome.gameOver);
      expect(s.repairsLeft, 0);
      expect(s.grid.hasLegalMove, isFalse,
          reason: 'ゲームオーバーなのに打てる手が残っている');
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
      expect(s.isGameOver, isTrue,
          reason: 'テストの前提: seed 9 はゲームオーバーで終わるはず');
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
      expect(s.isGameOver, isTrue,
          reason: 'テストの前提: seed 9 はゲームオーバーで終わるはず');
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
      expect(s.isGameOver, isTrue,
          reason: 'テストの前提: seed 9 はゲームオーバーで終わるはず');
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
