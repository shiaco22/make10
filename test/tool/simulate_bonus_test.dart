import 'package:flutter_test/flutter_test.dart';

import '../../tool/simulate_bonus.dart';

void main() {
  // 300 回の試行は 1 分弱かかる。既定のタイムアウトを延ばす。
  group('仕様の実測値(§6・§3.2)を実エンジンで再現する', () {
    test('10 到達率・タップ数・スコアの中央値が仕様 §6 の範囲に入る', () {
      final result = simulate(runs: 300, seed: 20260903, policy: 'score');

      // 上限(kBonusRepairLimit)を入れたことで「10 に必ず到達する」は
      // もう成り立たない。1 ゲームは必ずクリアかゲームオーバーの
      // どちらかで終わるはず ── そうならない試行があれば
      // `_play` の安全弁 cap(既定 20000 タップ)に達したことになり、
      // 実エンジンの不変条件が壊れている。
      expect(result.wins + result.gameOvers, result.runs,
          reason: '勝ちでもゲームオーバーでもない試行がある');

      // 仕様 §6(Dart の実エンジンで測定、runs=600, seed=20260905):
      // 10 到達率 40.5%、到達時タップ中央 93、GO 時タップ中央 94、
      // 全体スコア中央 859。ここは別シード・別試行数での実測なので
      // ぴったりは一致しない ── 乱数の話ではなく単に標本が違うため。
      // 仕様 §6 の数値自体、Python 再実装での測定値(10 到達率 31.0%
      // など)とは無視できない差があったが、実エンジンを複数のシード・
      // 試行数で測って再現した値なので、実エンジンの値を正としている
      // (詳細は仕様 §6 の「Python 再実装との差」を参照)。
      expect(result.wins / result.runs, closeTo(0.405, 0.10),
          reason: '10 到達率が仕様 §6 とずれている: '
              '実測 ${result.wins}/${result.runs}、仕様 40.5%');
      expect(result.tapsMedian, closeTo(93, 19),
          reason: '到達時タップ中央が仕様 §6 とずれている: '
              '実測 ${result.tapsMedian}、仕様 93');
      expect(result.goTapsMedian, closeTo(94, 19),
          reason: 'GO 時タップ中央が仕様 §6 とずれている: '
              '実測 ${result.goTapsMedian}、仕様 94');
      expect(result.scoreMedian, closeTo(859, 172),
          reason: '全体スコア中央が仕様 §6 とずれている: '
              '実測 ${result.scoreMedian}、仕様 859');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('詰みの修復が最大値のマスを動かさない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      expect(result.repairsTopMoved, 0,
          reason: '修復で最大値のマスが動いた(仕様 §3.2 は 0.0%)');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('修復 1 回あたりの書き換えマス数が少ない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      // 仕様 §3.2: 3.0 マス。全並べ替えの 21.2 マスとは明確に違う水準。
      // この性質は詰み修復そのもの(BonusGrid.repairIfStuck)の話で、
      // 入れ替え上限(Task 7 で足した cap)は「修復するかどうか」しか
      // 変えないので、実測値は上限の有無に関わらず変わらない。
      expect(result.cellsChangedPerRepair, lessThan(8),
          reason: '実測 ${result.cellsChangedPerRepair} マス、仕様 3.0 マス');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('全並べ替えへのフォールバックは稀にしか起こらない', () {
      // 仕様 §2.6・§11.5: `BonusMerge.usedFullShuffle` で実測すると、
      // 手順 2(全並べ替え)まで落ちる回数は試行(runs, seed)によって
      // 0〜数回程度で揺れる ── この実測(runs=300, seed=20260903)では
      // 0 回だったが、他のシードでは 1〜2 回観測されており、常に 0 とは
      // 限らない。ここでは「稀」であることを、十分な余裕を持たせた
      // 上限で検証する(常に 0 であることは主張しない)。
      final result = simulate(runs: 300, seed: 20260903, policy: 'score');
      expect(result.fallbacks, lessThan(20),
          reason: '実測は 0〜数回程度(仕様 §11.5)。十分緩い上限なので、'
              'これを超えたら手順 1(低い値からの引き直し)が退化している'
              '疑いがある: 実測 ${result.fallbacks} 回');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
