// 仕様 §6.3 / §11.2 が求める「生成物の整合性」を担保するテスト。
//
// tool/generate_puzzles.dart を `dart run` するのは flutter test の中では
// 扱いにくいので、生成ロジック本体（buildPuzzleTable）を in-process で
// 呼び出し、コミット済みの assets/puzzles.json と突き合わせる。
// 生成器を再実装すると「テストと生成器が同じ勘違いを共有していたら
// どちらも気づけない」ため、必ず本物のソルバーと Puzzle.toJson を通す
// buildPuzzleTable() / allSolutionsUseDivision() をそのまま使う。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/puzzle.dart';
import 'package:make10/domain/solver.dart';

import '../../tool/generate_puzzles.dart' as gen;

void main() {
  test(
      'regenerating the table from the live solver reproduces '
      'assets/puzzles.json byte for byte', () {
    // 仕様 §6.3: 「再生成した結果がコミット済みのものと一致する」ことが、
    // ソルバーとテーブルの乖離を防ぐ唯一の仕組みだと明記されている。
    // ソルバーが「現在は解なし」と記録されている組み合わせだけに影響する
    // 変更をしても、548 件すべての n は変わらないため既存テストは
    // 素通りしてしまう -- これはそれを検出する。
    final regenerated = gen.buildPuzzleTable().json;
    final committed = File('assets/puzzles.json').readAsStringSync();
    expect(regenerated, committed);
  });

  test(
      "each entry's div flag matches a live solver rerun, and exactly 101 "
      'entries require division', () {
    // 仕様 §11.2: 生成物の整合性は n だけでなく div も再検証を求めている。
    // puzzles_asset_test.dart は n しか照合していない。
    final data = jsonDecode(File('assets/puzzles.json').readAsStringSync())
        as Map<String, dynamic>;
    final puzzles = (data['puzzles'] as List)
        .map((e) => Puzzle.fromJson(e as Map<String, dynamic>))
        .toList();

    var divCount = 0;
    for (final puzzle in puzzles) {
      final solutions = solve(puzzle.digits);
      final requiresDivision = gen.allSolutionsUseDivision(solutions);
      expect(requiresDivision, puzzle.requiresDivision,
          reason: 'div mismatch for ${puzzle.key}');
      if (requiresDivision) divCount++;
    }
    expect(divCount, 101);
  });
}
