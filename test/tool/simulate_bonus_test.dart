import 'package:flutter_test/flutter_test.dart';

import '../../tool/simulate_bonus.dart';

void main() {
  // 300 回の試行は 1 分弱かかる。既定のタイムアウトを延ばす。
  group('仕様 §3.1 の実測値を実エンジンで再現する', () {
    test('点数最大の方針で 10 に必ず到達し、タップ数が仕様の範囲に入る', () {
      final result = simulate(runs: 300, seed: 20260903, policy: 'score');

      expect(result.wins, 300, reason: '10 に到達しない試行がある');

      // 仕様 §3.1: p10 84 / 中央値 104 / p90 131。
      // 乱数実装が Python と違うので同じ値にはならない。分布として
      // 一致していることを ±20% で見る。
      expect(result.tapsMedian, closeTo(104, 21),
          reason: 'タップ数の中央値が仕様 §3.1 とずれている: '
              '実測 ${result.tapsMedian}、仕様 104');
      expect(result.tapsP10, closeTo(84, 17));
      expect(result.tapsP90, closeTo(131, 26));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('詰みの修復が最大値のマスを動かさない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      expect(result.repairsTopMoved, 0,
          reason: '修復で最大値のマスが動いた(仕様 §3.2 は 0.0%)');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('修復 1 回あたりの書き換えマス数が少ない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      // 仕様 §3.2: 3.0 マス。全並べ替えの 21.2 マスとは明確に違う水準。
      expect(result.cellsChangedPerRepair, lessThan(8),
          reason: '実測 ${result.cellsChangedPerRepair} マス、仕様 3.0 マス');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('全並べ替えへのフォールバックに到達しない', () {
      final result = simulate(runs: 100, seed: 7, policy: 'score');
      expect(result.fallbacks, 0,
          reason: '低い値の引き直しで解決せず全並べ替えに落ちた');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
