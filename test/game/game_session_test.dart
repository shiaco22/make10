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
}
