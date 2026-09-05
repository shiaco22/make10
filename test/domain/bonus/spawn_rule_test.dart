import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/spawn_rule.dart';

void main() {
  group('spawnValue の範囲', () {
    test('盤面の最大が 1 なら 1 しか返さない', () {
      final random = Random(0);
      for (var i = 0; i < 200; i++) {
        expect(spawnValue(1, random), 1);
      }
    });

    test('盤面の最大が 2 でも 1 しか返さない', () {
      final random = Random(0);
      for (var i = 0; i < 200; i++) {
        expect(spawnValue(2, random), 1);
      }
    });

    test('上端は max - 1 で、それを超えない', () {
      final random = Random(1);
      for (var i = 0; i < 2000; i++) {
        final v = spawnValue(6, random);
        expect(v, greaterThanOrEqualTo(1));
        expect(v, lessThanOrEqualTo(5));
      }
    });

    test('下端は常に 1 で、盤面が育っても 1 は湧き続ける', () {
      // 仕様 §2.4: サンプルゲームで最大 9 の局面でも 1 が出ていた。
      // 範囲を [m-3, m-1] にすると 1 の出現率が 0% になり観測と矛盾する。
      final random = Random(2);
      var sawOne = false;
      for (var i = 0; i < 2000 && !sawOne; i++) {
        if (spawnValue(9, random) == 1) sawOne = true;
      }
      expect(sawOne, isTrue, reason: '盤面の最大が 9 のとき 1 が一度も湧かなかった');
    });
  });

  group('spawnWeights', () {
    test('重みは 1/sqrt(v)', () {
      final weights = spawnWeights(5); // 範囲 1..4
      expect(weights.length, 4);
      expect(weights[0], closeTo(1.0, 1e-12));
      expect(weights[1], closeTo(1 / sqrt(2), 1e-12));
      expect(weights[2], closeTo(1 / sqrt(3), 1e-12));
      expect(weights[3], closeTo(1 / sqrt(4), 1e-12));
    });

    test('盤面の最大が 1 でも 2 でも長さ 1', () {
      expect(spawnWeights(1).length, 1);
      expect(spawnWeights(2).length, 1);
    });
  });

  test('盤面の最大が 9 のときの分布が仕様 §2.4 の表と一致する', () {
    // 仕様の表は 20 万回の抽選で実測したもの。ここでは 10 万回で
    // ±0.6 ポイントの許容を置く(Random を固定しているので決定的)。
    const expected = <int, double>{
      1: 22.9, 2: 16.0, 3: 13.3, 4: 11.4,
      5: 10.1, 6: 9.3, 7: 8.7, 8: 8.1,
    };
    const draws = 100000;
    final random = Random(20260903);
    final counts = <int, int>{};
    for (var i = 0; i < draws; i++) {
      final v = spawnValue(9, random);
      counts[v] = (counts[v] ?? 0) + 1;
    }
    expect(counts.keys.toList()..sort(), expected.keys.toList()..sort(),
        reason: '9 が湧いてはいけない(範囲は 1..8)');
    for (final entry in expected.entries) {
      final actual = counts[entry.key]! / draws * 100;
      expect(actual, closeTo(entry.value, 0.6),
          reason: '値 ${entry.key} の出現率が仕様の表とずれている');
    }
  });
}
