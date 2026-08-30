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
}
