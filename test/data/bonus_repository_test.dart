import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid sampleGrid() => gridOf([
      [1, 1, 3, 1, 2],
      [3, 1, 2, 3, 1],
      [2, 3, 1, 2, 3],
      [1, 2, 3, 1, 2],
      [3, 1, 2, 3, 1],
    ]);

BonusGrid advancedGrid() => gridOf([
      [2, 2, 3, 1, 2],
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

/// `setValue` の確定をテストから握れる [SharedPreferencesStorePlatform]。
///
/// 標準の [InMemorySharedPreferencesStore] は `setValue` を await 抜きで
/// 即座に確定させるので、呼び出しを重ねても常に呼び出し順に反映され、
/// 「ストレージ層に複数の書き込みが同時に issue されている」状況(実機
/// では Android/iOS のプラットフォームチャネル越しの書き込みで起こり
/// 得る。完了の順序が入れ替わると、より新しいデータをより古いデータが
/// 上書きしてしまう)を再現できない。ここでは `setValue` の確定を
/// [releaseOldest] を呼ぶまで保留し、テストが「いま何件が確定を待って
/// いるか」を [pendingCount] で観測できるようにする。
class _ControllableStore extends InMemorySharedPreferencesStore {
  _ControllableStore() : super.empty();

  final List<_PendingWrite> _pending = [];

  /// まだ [releaseOldest] していない `setValue` 呼び出しの数。
  ///
  /// 直列化されていれば、この値が 2 以上になることは無い —— 前の
  /// 書き込みが確定するまで次の setValue が呼ばれないため。
  int get pendingCount => _pending.length;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final completer = Completer<bool>();
    _pending.add(_PendingWrite(valueType, key, value, completer));
    return completer.future;
  }

  /// もっとも先に呼ばれた(まだ確定していない)`setValue` を今ストレージへ
  /// 確定させる。
  Future<void> releaseOldest() async {
    final write = _pending.removeAt(0);
    await super.setValue(write.valueType, write.key, write.value);
    write.completer.complete(true);
  }
}

class _PendingWrite {
  _PendingWrite(this.valueType, this.key, this.value, this.completer);
  final String valueType;
  final String key;
  final Object value;
  final Completer<bool> completer;
}

/// 最初の [failCount] 回の `setValue` を失敗させる
/// [SharedPreferencesStorePlatform]。
class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore(this.failCount) : super.empty();

  final int failCount;
  int _calls = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _calls++;
    if (_calls <= failCount) {
      throw StateError('setValue failed (test)');
    }
    return super.setValue(valueType, key, value);
  }
}

/// [condition] が true になるまで、最大 [maxTurns] 回イベントループを
/// 1 ティック回す。ポーリングの往復を各テストで書き直さずに済ませる。
Future<void> _pumpUntil(bool Function() condition, {int maxTurns = 50}) async {
  for (var i = 0; i < maxTurns && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// イベントループを [turns] 回だけ回す。条件を待つのではなく、
/// 「これ以上進まないこと」を確かめたいときに使う。
Future<void> _pump(int turns) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
      await repo.saveProgress(advanced, 340, 0);

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

  group('保存の順序', () {
    test('await せずに複数回呼んでも、確定するのは最後に呼んだ盤面', () async {
      // 標準の InMemorySharedPreferencesStore は setValue を await 抜きで
      // 即座に確定させるため、この単純な「連続して呼ぶだけ」のケースは
      // 直列化する前のコードでも実は通ってしまう(呼び出しが 1 度も
      // await で割り込まれないので、すべての同期的なフィールド代入が
      // 先に完了してから初めて非同期側が読みに行くため)。ここでは
      // 「直列化してもこの結果を壊していない」ことを固定するためのもので、
      // 直列化そのものが効くかどうかは下のテストで見る。
      final repo = await loaded();
      final first = repo.saveProgress(sampleGrid(), 10, 0);
      final second = repo.saveProgress(advancedGrid(), 20, 0);
      await first;
      await second;

      final reloaded = await loaded();
      expect(reloaded.inProgressGrid!.cells, advancedGrid().cells);
      expect(reloaded.inProgressScore, 20);
    });

    test('2 件目の書き込みは、1 件目がストレージへ確定するまで発行されない', () async {
      // BonusSession.tap は saveProgress(...).ignore() を await せずに
      // 1 手ごとに呼ぶ。_save() には await が 2 箇所あるので、直列化して
      // いなければ、2 回の setValue が同時に「発行済みで未確定」になり
      // 得る。実機ではその 2 つがプラットフォームチャネル越しにどちらの
      // 順で確定するか保証が無く、完了が入れ替わればより新しいデータを
      // より古いデータが上書きする。直列化さえできていれば、ストレージに
      // 同時に 2 件以上の書き込みが issue されること自体が無くなるので、
      // 完了順の入れ替わりは構造的に起こり得ない —— それをここで見る。
      final store = _ControllableStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();

      final repo = BonusRepository();
      await repo.load();

      // 1 件目(古いデータ)。setValue が発行されるまで待つ。
      final first = repo.saveProgress(sampleGrid(), 10, 0);
      await _pumpUntil(() => store.pendingCount >= 1);
      expect(store.pendingCount, 1);

      // 2 件目(新しいデータ)を、1 件目を確定させる前に呼ぶ。
      final second = repo.saveProgress(advancedGrid(), 20, 0);
      await _pump(10);
      expect(store.pendingCount, 1,
          reason: '直列化されておらず、1 件目の確定前に 2 件目が発行された');

      // 1 件目を確定させる。鎖でつながれていれば、これで初めて 2 件目が
      // 発行される。
      await store.releaseOldest();
      await _pumpUntil(() => store.pendingCount >= 1);
      await store.releaseOldest();

      await first;
      await second;

      // 別プロセスでの再読み込みを模すため、インメモリの
      // SharedPreferences キャッシュを介さず、ストレージそのものから
      // 読み直す。
      SharedPreferences.resetStatic();
      final reloaded = BonusRepository();
      await reloaded.load();
      expect(reloaded.inProgressGrid!.cells, advancedGrid().cells);
      expect(reloaded.inProgressScore, 20);
    });

    test('書き込みが失敗しても、以降の保存を巻き添えにしない', () async {
      // 最初の 1 回だけ失敗するストアを使う。直列化の実装が「前回の
      // Future をそのまま次の then に渡す」だけだと、失敗した Future が
      // 鎖に残り続け、それ以降の保存が全部巻き添えで失敗する。
      final store = _FlakyStore(1);
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();

      final repo = BonusRepository();
      await repo.load();

      // 1 回目は失敗する。BonusSession.tap の .ignore() と同じ扱いで
      // ここでも例外は握りつぶす — 失敗そのものはこのテストの対象外。
      await repo.saveProgress(sampleGrid(), 10, 0).catchError((_) => null);

      // 2 回目は成功するはず。直前の失敗が鎖に残っていれば、これも
      // 巻き添えで失敗する。
      await repo.saveProgress(advancedGrid(), 20, 0);

      SharedPreferences.resetStatic();
      final reloaded = BonusRepository();
      await reloaded.load();
      expect(reloaded.inProgressGrid!.cells, advancedGrid().cells,
          reason: '直前の書き込み失敗が以降の保存を巻き添えにした');
      expect(reloaded.inProgressScore, 20);
    });
  });
}
