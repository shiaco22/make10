import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/history_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty', () async {
    final repo = HistoryRepository();
    await repo.load();
    expect(repo.recent(Difficulty.easy), isEmpty);
  });

  test('records newest first', () async {
    final repo = HistoryRepository();
    await repo.load();
    await repo.record(Difficulty.hard, '1,5,5,5');
    await repo.record(Difficulty.hard, '1,1,1,4');
    expect(repo.recent(Difficulty.hard), ['1,1,1,4', '1,5,5,5']);
  });

  test('keeps at most kHistoryLimit entries per difficulty', () async {
    final repo = HistoryRepository();
    await repo.load();
    for (var i = 0; i < kHistoryLimit + 10; i++) {
      await repo.record(Difficulty.normal, 'key$i');
    }
    final recent = repo.recent(Difficulty.normal);
    expect(recent, hasLength(kHistoryLimit));
    expect(recent.first, 'key${kHistoryLimit + 9}');
    expect(recent.contains('key0'), isFalse);
  });

  test('difficulties are tracked separately', () async {
    final repo = HistoryRepository();
    await repo.load();
    await repo.record(Difficulty.easy, 'a');
    expect(repo.recent(Difficulty.hard), isEmpty);
  });

  test('survives a reload', () async {
    final first = HistoryRepository();
    await first.load();
    await first.record(Difficulty.easy, '0,1,2,8');

    final second = HistoryRepository();
    await second.load();
    expect(second.recent(Difficulty.easy), ['0,1,2,8']);
  });

  test('falls back to empty history when stored json is corrupt', () async {
    SharedPreferences.setMockInitialValues({'make10.history': 'not json'});
    final repo = HistoryRepository();
    await repo.load();
    expect(repo.recent(Difficulty.easy), isEmpty);
  });

  test(
      'falls back to empty history for every difficulty when one holds a '
      'non-string element', () async {
    // Valid JSON, wrong shape: 'normal' has a non-string element. A lazy
    // list.cast<String>() would let this through load() unnoticed and only
    // throw later, when the list is actually read.
    SharedPreferences.setMockInitialValues({
      'make10.history': jsonEncode({
        'version': 1,
        'easy': ['0,1,2,8'],
        'normal': ['1,2,3,4', 5],
        'hard': ['1,5,5,5'],
      }),
    });
    final repo = HistoryRepository();
    await repo.load();
    for (final difficulty in Difficulty.values) {
      expect(repo.recent(difficulty), isEmpty,
          reason: 'expected empty history for ${difficulty.key}');
    }
  });

  test(
      'a non-list entry for one difficulty is skipped without discarding '
      "a well-formed sibling entry (unlike StatsRepository's all-or-"
      'nothing recovery from a nested cast failure)', () async {
    // Valid JSON, wrong shape: 'easy' is a number instead of a list, but
    // 'hard' is a well-formed list. load() checks each difficulty's shape
    // independently (`if (list is List)`) and only skips the ones that
    // don't match -- seeding only the malformed key (as this test used to)
    // made "every difficulty comes back empty" hold trivially, since
    // 'normal' and 'hard' were never present either way, and it implied a
    // blanket wipe the code doesn't actually perform. Seeding a good
    // sibling alongside the bad entry surfaces the real, narrower recovery.
    SharedPreferences.setMockInitialValues({
      'make10.history': jsonEncode({
        'version': 1,
        'easy': 42,
        'hard': ['1,5,5,5'],
      }),
    });
    final repo = HistoryRepository();
    await repo.load();
    expect(repo.recent(Difficulty.easy), isEmpty,
        reason: 'expected empty history for the malformed easy entry');
    expect(repo.recent(Difficulty.normal), isEmpty,
        reason: 'normal was never present in the seeded payload');
    expect(repo.recent(Difficulty.hard), ['1,5,5,5'],
        reason: 'a well-formed sibling entry should still load');
  });
}
