// 全 715 通りを解いて assets/puzzles.json を生成する。
// 実行: C:/flutter/bin/dart.bat run tool/generate_puzzles.dart
//
// lib/domain/solver.dart をそのまま使う。ソルバーは 1 実装しか持たない。
import 'dart:convert';
import 'dart:io';

import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/domain/puzzle.dart';
import 'package:make10/domain/solver.dart';

/// 0〜9 から重複ありで 4 つ選ぶ組み合わせを昇順で列挙する。
Iterable<List<int>> allCombinations() sync* {
  for (var a = 0; a <= 9; a++) {
    for (var b = a; b <= 9; b++) {
      for (var c = b; c <= 9; c++) {
        for (var d = c; d <= 9; d++) {
          yield [a, b, c, d];
        }
      }
    }
  }
}

void main() {
  // List を Map のキーにすると同一性比較になるので、レコードのリストで持つ。
  final solvable = <({List<int> digits, int count, bool requiresDivision})>[];
  var total = 0;

  for (final digits in allCombinations()) {
    total++;
    final solutions = solve(digits);
    if (solutions.isEmpty) continue;
    solvable.add((
      digits: digits,
      count: solutions.length,
      // 全解が除算を含むなら、除算なしでは解けない。
      requiresDivision:
          solutions.every((s) => s.steps.any((step) => step.op == Op.div)),
    ));
  }

  final thresholds =
      computeThresholds([for (final e in solvable) e.count]);

  final puzzles = [
    for (final e in solvable)
      Puzzle(
        digits: e.digits,
        solutionCount: e.count,
        requiresDivision: e.requiresDivision,
        difficulty: difficultyFor(e.count, thresholds),
      ),
  ];

  puzzles.sort((a, b) => a.key.compareTo(b.key));

  final payload = {
    'version': 1,
    'rule': {'target': kTarget, 'division': 'exact', 'negatives': true},
    'thresholds': thresholds.toJson(),
    'puzzles': puzzles.map((p) => p.toJson()).toList(),
  };

  File('assets/puzzles.json')
      .writeAsStringSync('${jsonEncode(payload)}\n');

  stderr.writeln('total: $total  solvable: ${puzzles.length}  '
      'thresholds: hard<=${thresholds.hard} normal<=${thresholds.normal}');
}
