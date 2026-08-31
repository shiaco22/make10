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

/// 全解が除算を含むか。全解が除算を要するなら、除算なしでは解けない。
///
/// buildPuzzleTable() とテスト（generate_puzzles_test.dart）の双方から
/// 呼ぶことで、`div` フラグの定義を 1 箇所にする。
bool allSolutionsUseDivision(List<Solution> solutions) =>
    solutions.every((s) => s.steps.any((step) => step.op == Op.div));

/// [buildPuzzleTable] の結果。JSON 本体と、main() が stderr に出す要約用の
/// 内訳をまとめて返す。
class GeneratedPuzzleTable {
  final String json;
  final int totalCombinations;
  final int solvableCount;
  final Thresholds thresholds;

  const GeneratedPuzzleTable({
    required this.json,
    required this.totalCombinations,
    required this.solvableCount,
    required this.thresholds,
  });
}

/// assets/puzzles.json の中身を組み立てる。
///
/// main()（CLI から `assets/puzzles.json` に書き出す）とテスト
/// （再生成がコミット済みファイルと一致することを検証する）の両方が
/// これを呼ぶ。生成ロジックを 1 箇所にまとめることで、テストが
/// 「生成器の再実装」ではなく「生成器そのもの」を検証できる。
GeneratedPuzzleTable buildPuzzleTable() {
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
      requiresDivision: allSolutionsUseDivision(solutions),
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

  return GeneratedPuzzleTable(
    json: '${jsonEncode(payload)}\n',
    totalCombinations: total,
    solvableCount: puzzles.length,
    thresholds: thresholds,
  );
}

void main() {
  final table = buildPuzzleTable();

  File('assets/puzzles.json').writeAsStringSync(table.json);

  stderr.writeln('total: ${table.totalCombinations}  '
      'solvable: ${table.solvableCount}  '
      'thresholds: hard<=${table.thresholds.hard} '
      'normal<=${table.thresholds.normal}');
}
