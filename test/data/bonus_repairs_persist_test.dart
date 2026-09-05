import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid playableGrid() => BonusGrid.of(const [
      1, 1, 3, 1, 2, //
      3, 1, 2, 3, 1, //
      2, 3, 1, 2, 3, //
      1, 2, 3, 1, 2, //
      3, 1, 2, 3, 1, //
    ]);

Future<BonusRepository> loaded() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('開始直後は 0', () async {
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    expect(repo.inProgressRepairsUsed, 0);
  });

  test('保存して読み直せる', () async {
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    await repo.saveProgress(playableGrid(), 340, 6);

    final reloaded = await loaded();
    expect(reloaded.inProgressRepairsUsed, 6);
    expect(reloaded.inProgressScore, 340);
  });

  test('中断して再開しても入れ替えの残りが戻らない', () async {
    // 抜け道の本体。ここが通らないと Task 3 の上限が意味を失う。
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    await repo.saveProgress(playableGrid(), 500, kBonusRepairLimit);

    final reloaded = await loaded();
    expect(reloaded.inProgressRepairsUsed, kBonusRepairLimit,
        reason: '再開で入れ替えの使用回数がリセットされている');
  });

  test('終了で 0 に戻る', () async {
    final repo = await loaded();
    await repo.earn('2026-09-05');
    await repo.startGame('2026-09-05', playableGrid());
    await repo.saveProgress(playableGrid(), 500, 8);
    await repo.finish(500);
    expect(repo.inProgressRepairsUsed, 0);

    final reloaded = await loaded();
    expect(reloaded.inProgressRepairsUsed, 0);
    expect(reloaded.hasInProgress, isFalse);
  });

  group('壊れた・古いデータ', () {
    test('repairsUsed が無い古い保存データは 0 として読む', () async {
      // 上限を入れる前に保存された途中状態。捨ててゲームを失わせるより、
      // 上限が緩む方に倒す(仕様 §7)。
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'bestScore': 700,
          'playedOn': '2026-09-05',
          'inProgress': {'grid': playableGrid().cells, 'score': 120},
        }),
      });
      final repo = await loaded();
      expect(repo.hasInProgress, isTrue);
      expect(repo.inProgressRepairsUsed, 0);
      expect(repo.inProgressScore, 120);
    });

    test('負の値は 0 に丸める', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': playableGrid().cells,
            'score': 10,
            'repairsUsed': -5,
          },
        }),
      });
      final repo = await loaded();
      expect(repo.inProgressRepairsUsed, 0);
    });

    test('上限を超える値は上限に丸める', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': playableGrid().cells,
            'score': 10,
            'repairsUsed': 999,
          },
        }),
      });
      final repo = await loaded();
      expect(repo.inProgressRepairsUsed, kBonusRepairLimit);
    });

    test('型が違えば 0 として読む', () async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 1,
          'inProgress': {
            'grid': playableGrid().cells,
            'score': 10,
            'repairsUsed': 'たくさん',
          },
        }),
      });
      final repo = await loaded();
      // 途中状態ごと捨てるか 0 として読むかは実装次第だが、例外を
      // 外へ投げてはいけない。
      expect(repo.inProgressRepairsUsed, 0);
    });
  });
}
