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
      // `data['bestScore'] as int?` は 'たくさん' のような non-null な
      // 不一致の型に対して null を返さず TypeError を投げる(`as T?` が
      // 素通しするのは null だけ)。ここでは outer の catch がそれを拾い、
      // レコード全体を既定値に戻す -- unlockedOn 側の不一致を個別に
      // 見るまでもなく、ticket もまとめて初期化されることまで確認する。
      expect(repo.bestScore, 0);
      expect(repo.ticket.unlockedOn, isNull);
      expect(repo.ticket.playedOn, isNull);
      expect(repo.hasInProgress, isFalse);
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

    test('盤面に int でない要素が混ざっていれば途中状態を破棄する', () async {
      // このテストが実際に固定しているのは「壊れた要素があれば途中状態
      // だけを捨て、bestScore など他のフィールドは残る」という契約だけ。
      // `_decodeGrid` の `List<int>.from(...)` を `cast<int>()` に変えても
      // このテストは落ちない — [BonusGrid.of] 内部の `List<int>.of(cells)`
      // と、このテストのすぐ下にある範囲チェックの `for` ループが、それぞれ
      // 独立にリストを走査して先に強制評価してしまうため。
      // `List<int>.from(...)` を選ぶ理由そのものは
      // `lib/data/bonus_repository.dart` の `_decodeGrid` 側のコメントを
      // 参照(そちらが最後の防衛線として残っている)。
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
