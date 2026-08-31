import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/history_repository.dart';
import 'package:make10/data/puzzle_repository.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/game/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

void main() {
  late GameSession session;
  late StatsRepository stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final history = HistoryRepository();
    await history.load();
    final puzzles = PuzzleRepository(history, random: Random(7));
    await puzzles.loadFromString(realPuzzlesJson());
    stats = StatsRepository();
    await stats.load();
    session = GameSession(
      puzzles: puzzles,
      stats: stats,
      difficulty: Difficulty.normal,
    );
    session.start();
  });

  test('starts with four cards and nothing selected', () {
    expect(session.board.cards, hasLength(4));
    expect(session.selectedCardId, isNull);
    expect(session.selectedOp, isNull);
    expect(session.phase, PhaseKind.playing);
  });

  test('tapping card then op then card performs a merge', () {
    final a = session.board.cards[0];
    final b = session.board.cards[1];
    session.tapCard(a.id);
    session.tapOp(Op.add);
    session.tapCard(b.id);
    expect(session.board.cards, hasLength(3));
    expect(session.selectedCardId, isNull);
    expect(session.selectedOp, isNull);
  });

  test('tapping the selected card again clears the selection', () {
    final a = session.board.cards[0];
    session.tapCard(a.id);
    session.tapCard(a.id);
    expect(session.selectedCardId, isNull);
  });

  test('tapping another operator replaces the pending one', () {
    session.tapCard(session.board.cards[0].id);
    session.tapOp(Op.add);
    session.tapOp(Op.mul);
    expect(session.selectedOp, Op.mul);
  });

  test('a rejected merge keeps the card and operator selected', () async {
    session = await sessionWithDigits([7, 2, 1, 1], stats);
    final seven = session.board.cards[0];
    final two = session.board.cards[1];
    session.tapCard(seven.id);
    session.tapOp(Op.div);
    session.tapCard(two.id);
    expect(session.board.cards, hasLength(4));
    expect(session.selectedCardId, seven.id);
    expect(session.selectedOp, Op.div);
    expect(session.lastRejection, isNotNull);
  });

  test('a rejected merge records which card was the target', () async {
    session = await sessionWithDigits([7, 2, 1, 1], stats);
    final seven = session.board.cards[0];
    final two = session.board.cards[1];
    session.tapCard(seven.id);
    session.tapOp(Op.div);
    session.tapCard(two.id);
    expect(session.lastRejectedCardId, two.id);
  });

  test('rejectionSeq advances on every rejection, even an identical repeat',
      () async {
    session = await sessionWithDigits([7, 2, 1, 1], stats);
    final seven = session.board.cards[0];
    final two = session.board.cards[1];
    session.tapCard(seven.id);
    session.tapOp(Op.div);
    session.tapCard(two.id);
    final firstSeq = session.rejectionSeq;
    expect(session.lastRejectedCardId, two.id);

    // 同じ相手へ、選択を崩さずもう一度。理由も対象カードも前回と同じだが、
    // CardTile が震えを再トリガーできるよう rejectionSeq は必ず変わる。
    session.tapCard(two.id);
    expect(session.lastRejection, isNotNull);
    expect(session.lastRejectedCardId, two.id);
    expect(session.rejectionSeq, isNot(firstSeq));
  });

  test('dismissRejection clears the message but keeps the selection',
      () async {
    session = await sessionWithDigits([7, 2, 1, 1], stats);
    final seven = session.board.cards[0];
    final two = session.board.cards[1];
    session.tapCard(seven.id);
    session.tapOp(Op.div);
    session.tapCard(two.id);
    expect(session.lastRejection, isNotNull);
    final seqAtRejection = session.rejectionSeq;

    session.dismissRejection();

    expect(session.lastRejection, isNull);
    expect(session.lastRejectedCardId, isNull);
    // 消去はユーザーの選択を壊さない -- 仕様上維持が必須（§2.5）。
    expect(session.selectedCardId, seven.id);
    expect(session.selectedOp, Op.div);
    // 消去自体は新しい拒否ではないので seq は増えない。
    expect(session.rejectionSeq, seqAtRejection);
  });

  test('dismissRejection is a no-op when there is nothing to dismiss', () {
    expect(session.lastRejection, isNull);
    expect(() => session.dismissRejection(), returnsNormally);
    expect(session.lastRejection, isNull);
    expect(session.selectedCardId, isNull);
  });

  test('clearing the board records a solve and moves to cleared phase', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).solved, 1);
  });

  test('undo steps back one merge', () {
    session.tapCard(session.board.cards[0].id);
    session.tapOp(Op.add);
    session.tapCard(session.board.cards[1].id);
    expect(session.board.cards, hasLength(3));
    session.undo();
    expect(session.board.cards, hasLength(4));
  });

  test('reset returns to four cards after several merges', () {
    session.tapCard(session.board.cards[0].id);
    session.tapOp(Op.add);
    session.tapCard(session.board.cards[1].id);
    session.tapCard(session.board.cards[0].id);
    session.tapOp(Op.add);
    session.tapCard(session.board.cards[1].id);
    session.resetBoard();
    expect(session.board.cards, hasLength(4));
  });

  test('requestHint exposes a move on a solvable board', () {
    session.requestHint();
    expect(session.hintMove, isNotNull);
    expect(session.deadEndNotice, isFalse);
  });

  test('requestHint flags a dead end instead of a move', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    // 3*7=21 に進むと 4,9,21 になり、ここから 10 は作れない（実測で確認済み）。
    // 3*4=12 は詰みではない。12,7,9 には 12+7-9=10 など 5 通りの解がある。
    final three = session.board.cards.firstWhere((c) => c.value == 3);
    final seven = session.board.cards.firstWhere((c) => c.value == 7);
    session.tapCard(three.id);
    session.tapOp(Op.mul);
    session.tapCard(seven.id);
    session.requestHint();
    expect(session.hintMove, isNull);
    expect(session.deadEndNotice, isTrue);
  });

  test('requestHint clears a stale rejection when a hint exists', () async {
    session = await sessionWithDigits([7, 2, 1, 1], stats);
    final seven = session.board.cards[0];
    final two = session.board.cards[1];
    session.tapCard(seven.id);
    session.tapOp(Op.div);
    session.tapCard(two.id);
    expect(session.lastRejection, isNotNull);

    session.requestHint();
    // 拒否理由が残ったままだと、GameScreen はヒントの成功を
    // 表示できず「割り切れません」を出し続けてしまう。
    expect(session.lastRejection, isNull);
    expect(session.hintMove, isNotNull);
  });

  test('requestHint clears a stale rejection on a dead-ended board', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    // 3*7=21 に進むと 4,9,21 になり、ここから 10 は作れない（詰み、実測で確認済み）。
    final three = session.board.cards.firstWhere((c) => c.value == 3);
    final seven = session.board.cards.firstWhere((c) => c.value == 7);
    session.tapCard(three.id);
    session.tapOp(Op.mul);
    session.tapCard(seven.id);

    // 詰みに進んだ盤面で、ヒント前にいったん拒否される合成を試みる。
    final nine = session.board.cards.firstWhere((c) => c.value == 9);
    final four = session.board.cards.firstWhere((c) => c.value == 4);
    session.tapCard(nine.id);
    session.tapOp(Op.div);
    session.tapCard(four.id);
    expect(session.lastRejection, isNotNull);

    session.requestHint();
    // 拒否理由が残ったままだと、GameScreen は詰み通知（戻しましょう）を
    // 表示できず「割り切れません」を出し続けてしまう。
    expect(session.lastRejection, isNull);
    expect(session.deadEndNotice, isTrue);
    expect(session.hintMove, isNull);
  });

  test('showAnswer locks the board and records the event', () async {
    session.showAnswer();
    expect(session.phase, PhaseKind.answerShown);
    expect(session.solutionSteps, isNotEmpty);
    final before = session.board.cards.length;
    session.tapCard(session.board.cards[0].id);
    session.tapOp(Op.add);
    session.tapCard(session.board.cards[1].id);
    expect(session.board.cards, hasLength(before));
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).answerShown, 1);
    expect(stats.practice(Difficulty.normal).solved, 0);
  });

  test('skip records a skip and deals a new puzzle', () async {
    final first = session.puzzle.key;
    session.skip();
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).skipped, 1);
    expect(session.puzzle.key, isNot(first));
    expect(session.phase, PhaseKind.playing);
  });

  test('a hinted clear counts as solved and bumps hintUsed', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    session.requestHint();
    playSolution(session);
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).solved, 1);
    expect(stats.practice(Difficulty.normal).hintUsed, 1);
  });

  test('re-clearing after undo does not double count the solve', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).solved, 1);
    final totalTimeMsAfterFirstClear =
        stats.practice(Difficulty.normal).totalTimeMs;

    // 仕様上 undo はクリア後も使える（別解を探したいだけかもしれない）。
    // ただし同じ配られた問題を再度クリアしても、統計は増えてはいけない。
    session.undo();
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);

    expect(stats.practice(Difficulty.normal).solved, 1);
    expect(
      stats.practice(Difficulty.normal).totalTimeMs,
      totalTimeMsAfterFirstClear,
    );
  });

  test('re-solving after resetBoard does not double count the solve', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).solved, 1);

    session.resetBoard();
    expect(session.board.cards, hasLength(4));
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);

    expect(stats.practice(Difficulty.normal).solved, 1);
  });

  test(
      'revealing the answer after undoing a clear does not record answerShown',
      () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).solved, 1);

    // クリア後の undo で playing に戻れても、この問題は既に 1 回
    // 結果を記録済みなので、答え表示は二重記録してはいけない。
    session.undo();
    session.showAnswer();
    expect(session.phase, PhaseKind.answerShown);
    await Future<void>.delayed(Duration.zero);

    expect(stats.practice(Difficulty.normal).answerShown, 0);
    expect(stats.practice(Difficulty.normal).solved, 1);
  });

  test('undo clears a stale dead-end notice', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    // 3*7=21 に進むと 4,9,21 になり、ここから 10 は作れない（詰み）。
    final three = session.board.cards.firstWhere((c) => c.value == 3);
    final seven = session.board.cards.firstWhere((c) => c.value == 7);
    session.tapCard(three.id);
    session.tapOp(Op.mul);
    session.tapCard(seven.id);
    session.requestHint();
    expect(session.deadEndNotice, isTrue);

    // undo で詰みではない [3,4,7,9] に戻ったのに通知が残っていると、
    // 解ける盤面を解けないと案内してしまう。
    session.undo();
    expect(session.deadEndNotice, isFalse);
  });

  test('undo clears a stale hint move', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    session.tapCard(session.board.cards[0].id);
    session.tapOp(Op.add);
    session.tapCard(session.board.cards[1].id);
    session.requestHint();
    expect(session.hintMove, isNotNull);

    // undo 後は盤面もカード ID も変わっているので、古い hintMove の
    // 位置情報を残すと無関係なカードを指してしまう。
    session.undo();
    expect(session.hintMove, isNull);
  });

  test('skip after a natural clear does not record an extra skip', () async {
    session = await sessionWithDigits([3, 4, 7, 9], stats);
    playSolution(session);
    expect(session.phase, PhaseKind.cleared);
    await Future<void>.delayed(Duration.zero);
    expect(stats.practice(Difficulty.normal).solved, 1);

    session.skip();
    await Future<void>.delayed(Duration.zero);

    expect(stats.practice(Difficulty.normal).skipped, 0);
  });
}
