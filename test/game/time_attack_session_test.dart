import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/game/time_attack_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

void main() {
  late StatsRepository stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stats = StatsRepository();
    await stats.load();
  });

  test('starts with a full clock and zero score', () async {
    final ta = await timeAttackWith(stats);
    expect(ta.remaining, kTimeAttackDuration);
    expect(ta.score, 0);
    expect(ta.isOver, isFalse);
  });

  test('assist is disabled during a time attack', () async {
    final ta = await timeAttackWith(stats);
    ta.session.requestHint();
    expect(ta.session.hintMove, isNull);
    ta.session.showAnswer();
    expect(ta.session.solutionSteps, isEmpty);
  });

  test('clearing a puzzle increments the score and deals another', () async {
    final ta = await timeAttackWith(stats);
    final first = ta.session.puzzle.key;
    playSolution(ta.session);
    expect(ta.score, 1);
    expect(ta.session.puzzle.key, isNot(first));
  });

  test('tick counts the clock down', () async {
    final ta = await timeAttackWith(stats);
    ta.tick(const Duration(seconds: 30));
    expect(ta.remaining, const Duration(seconds: 90));
    expect(ta.isOver, isFalse);
  });

  test('the run ends when the clock reaches zero', () async {
    final ta = await timeAttackWith(stats);
    ta.tick(kTimeAttackDuration);
    expect(ta.isOver, isTrue);
    expect(ta.remaining, Duration.zero);
  });

  test('a puzzle in progress at time-up does not score', () async {
    final ta = await timeAttackWith(stats);
    final card = ta.session.board.cards[0];
    ta.session.tapCard(card.id);
    ta.tick(kTimeAttackDuration);
    expect(ta.score, 0);
  });

  test('clearing after time-up is ignored', () async {
    final ta = await timeAttackWith(stats);
    ta.tick(kTimeAttackDuration);
    playSolution(ta.session);
    expect(ta.score, 0);
  });

  test('time-up records the run and reports a best update', () async {
    final ta = await timeAttackWith(stats);
    playSolution(ta.session);
    ta.tick(kTimeAttackDuration);
    await Future<void>.delayed(Duration.zero);
    expect(ta.bestUpdated, isTrue);
    expect(stats.timeAttack(Difficulty.normal).bestScore, 1);
    expect(stats.timeAttack(Difficulty.normal).playCount, 1);
  });

  test('time attack clears do not leak into practice statistics', () async {
    final ta = await timeAttackWith(stats);
    playSolution(ta.session);
    ta.session.skip();
    expect(ta.score, 1);
    await Future<void>.delayed(Duration.zero);
    // 120 秒の勝負で解いた問題をプラクティスの平均解答時間に混ぜない。
    expect(stats.practice(Difficulty.normal).solved, 0);
    expect(stats.practice(Difficulty.normal).skipped, 0);
  });

  test('a second weaker run does not update the best', () async {
    final first = await timeAttackWith(stats);
    playSolution(first.session);
    playSolution(first.session);
    first.tick(kTimeAttackDuration);
    await Future<void>.delayed(Duration.zero);

    final second = await timeAttackWith(stats);
    second.tick(kTimeAttackDuration);
    await Future<void>.delayed(Duration.zero);
    expect(second.bestUpdated, isFalse);
    expect(stats.timeAttack(Difficulty.normal).bestScore, 2);
  });
}
