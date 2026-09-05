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

/// (1,0)(1,1)(1,2) と (2,1)(2,2) の 2 が連結する盤面(5 マス)。
BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

/// [nearlyClearedGrid] に (4,2)(4,3) の 3 のペアを加えた盤面。
///
/// クリアの合成は (0,0)-(0,1) の外に一切手を触れない(仕様どおり、
/// クリア時は重力も補充も走らない)ので、このペアはクリア後もそのまま
/// 残る -- クリア後に「打てるはずの手」を用意して isOver のガードが
/// 本当に効いているかを確かめるための盤面。ガードが無いと、この手は
/// 合法手としてそのまま通ってしまう。
BonusGrid nearlyClearedGridWithSurvivingMove() => gridOf([
      [9, 9, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 3, 3, 1],
    ]);

/// [nearlyClearedGridWithSurvivingMove] と同じ理由で用意した、詰みが
/// 起きるように仕込んだ盤面。(0,0)-(0,1) の 3 を合成すると空きは
/// (0,1) の 1 マスだけになり、そこへの補充が唯一の乱数消費になる。
/// checkerboard になっている残りのマスには合法手が無いので、補充された
/// 値が隣接マスと一致するかどうかだけで詰みの有無が決まる
/// (シード値ごとの実測は [BonusSession] のテストのコメント参照)。
BonusGrid singleGapGrid() => gridOf([
      [3, 3, 1, 2, 1],
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

    test('詰みを修復した手では、修復したマス数がそのまま読める', () async {
      // 詰みは 8 タップに 1 回起きるので、UI が通知を出せるように
      // 直前の手で何マス書き換わったかを公開する。
      //
      // singleGapGrid().tap(0, Random(0)) は実測で必ず詰みが起きる
      // (checkerboard の唯一の空きマスへの補充が隣接マスと衝突しない
      // ため)。ここでは同じ盤面・同じシードをドメイン層へ直接渡し、
      // 「実際に何マス修復したか」を独立に計算してからセッション経由の
      // 値と突き合わせる。修復アルゴリズム自体の正しさは
      // bonus_grid_test.dart の役目で、ここで見たいのは BonusSession が
      // merge.repairedCells を lastRepairedCells へ取り違えずに渡して
      // いることだけ。
      const seed = 0;
      final expected = singleGapGrid().tap(0, Random(seed))!;
      expect(expected.repairedCells, greaterThan(0),
          reason: '前提が崩れている: このシードでは詰みが起きるはず');

      final session =
          sessionWith(await loadedRepo(), singleGapGrid(), seed: seed);
      session.tap(0);
      expect(session.lastRepairedCells, expected.repairedCells);
    });

    test('詰みが起きなかった手では 0 のまま', () async {
      // singleGapGrid().tap(0, Random(2)) は実測で詰みが起きない
      // (唯一の空きマスへの補充がたまたま隣接マスと同値になり、それ自体が
      // 合法手になるため)。上のテストと対になる、修復無しの経路。
      const seed = 2;
      final expected = singleGapGrid().tap(0, Random(seed))!;
      expect(expected.repairedCells, 0,
          reason: '前提が崩れている: このシードでは詰みが起きないはず');

      final session =
          sessionWith(await loadedRepo(), singleGapGrid(), seed: seed);
      session.tap(0);
      expect(session.lastRepairedCells, 0);
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
      // nearlyClearedGrid() だとクリア後の盤面がちょうど詰んでいて、
      // 2 回目の tap がどの添字でもドメイン層の不正な手チェックだけで
      // 弾かれてしまい、isOver のガードを外しても検出できない。
      // (4,2)-(4,3) の合法手がクリア後も残る盤面を使い、そこを狙って
      // 打つことで、ガード自体が効いていることを確かめる。
      final session = sessionWith(
          await loadedRepo(), nearlyClearedGridWithSurvivingMove());
      session.tap(0);
      expect(session.isOver, isTrue);
      final scoreAtClear = session.score;
      final cellsAtClear = session.grid.cells.toList();
      // クリア後も (4,2)-(4,3) = 添字 22/23 は合法手のまま残っている
      // (クリアの合成は重力も補充も走らせないため)。isOver のガードが
      // 無ければここが実際に合成されてしまう。
      expect(cellsAtClear[22], cellsAtClear[23],
          reason: '前提が崩れている: 22/23 に合法手が残っているはず');
      session.tap(22);
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
