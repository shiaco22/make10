import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts at zero', () async {
    final repo = StatsRepository();
    await repo.load();
    expect(repo.practice(Difficulty.easy).solved, 0);
    expect(repo.timeAttack(Difficulty.easy).bestScore, 0);
  });

  test('a hinted clear still counts as solved', () async {
    final repo = StatsRepository();
    await repo.load();
    await repo.recordSolved(Difficulty.hard, elapsedMs: 5000, usedHint: true);
    final stats = repo.practice(Difficulty.hard);
    expect(stats.solved, 1);
    expect(stats.hintUsed, 1);
  });

  test('a clear without a hint does not bump hintUsed', () async {
    final repo = StatsRepository();
    await repo.load();
    await repo.recordSolved(Difficulty.hard, elapsedMs: 3000, usedHint: false);
    expect(repo.practice(Difficulty.hard).hintUsed, 0);
  });

  test('shown answers and skips do not count as solved', () async {
    final repo = StatsRepository();
    await repo.load();
    await repo.recordAnswerShown(Difficulty.normal);
    await repo.recordSkipped(Difficulty.normal);
    final stats = repo.practice(Difficulty.normal);
    expect(stats.solved, 0);
    expect(stats.answerShown, 1);
    expect(stats.skipped, 1);
  });

  test('average time is derived from total and count', () async {
    final repo = StatsRepository();
    await repo.load();
    await repo.recordSolved(Difficulty.easy, elapsedMs: 4000, usedHint: false);
    await repo.recordSolved(Difficulty.easy, elapsedMs: 6000, usedHint: false);
    expect(repo.practice(Difficulty.easy).averageTimeMs, 5000);
  });

  test('average time is null before any clear', () async {
    final repo = StatsRepository();
    await repo.load();
    expect(repo.practice(Difficulty.easy).averageTimeMs, isNull);
  });

  test('time attack reports whether the best score improved', () async {
    final repo = StatsRepository();
    await repo.load();
    expect(await repo.recordTimeAttack(Difficulty.easy, 7), isTrue);
    expect(await repo.recordTimeAttack(Difficulty.easy, 5), isFalse);
    expect(await repo.recordTimeAttack(Difficulty.easy, 9), isTrue);
    final stats = repo.timeAttack(Difficulty.easy);
    expect(stats.bestScore, 9);
    expect(stats.playCount, 3);
  });

  test('survives a reload', () async {
    final first = StatsRepository();
    await first.load();
    await first.recordSolved(Difficulty.hard, elapsedMs: 1000, usedHint: false);

    final second = StatsRepository();
    await second.load();
    expect(second.practice(Difficulty.hard).solved, 1);
  });

  test('falls back to zeros when stored json is corrupt', () async {
    SharedPreferences.setMockInitialValues({'make10.stats': '<<broken>>'});
    final repo = StatsRepository();
    await repo.load();
    expect(repo.practice(Difficulty.easy).solved, 0);
  });
}
