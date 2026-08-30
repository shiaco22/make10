import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/puzzle.dart';
import 'package:make10/domain/solver.dart';

void main() {
  late Map<String, dynamic> data;
  late List<Puzzle> puzzles;

  setUpAll(() {
    data = jsonDecode(File('assets/puzzles.json').readAsStringSync())
        as Map<String, dynamic>;
    puzzles = (data['puzzles'] as List)
        .map((e) => Puzzle.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  test('records exactly the 548 solvable combinations', () {
    expect(puzzles, hasLength(548));
  });

  test('thresholds match the verified percentiles', () {
    final t = Thresholds.fromJson(data['thresholds'] as Map<String, dynamic>);
    expect(t.hard, 9);
    expect(t.normal, 26);
  });

  test('difficulty split matches the verified distribution', () {
    int countOf(Difficulty d) =>
        puzzles.where((p) => p.difficulty == d).length;
    expect(countOf(Difficulty.hard), 184);
    expect(countOf(Difficulty.normal), 192);
    expect(countOf(Difficulty.easy), 172);
  });

  test('every recorded puzzle is actually solvable with the stated count', () {
    for (final puzzle in puzzles) {
      expect(solve(puzzle.digits).length, puzzle.solutionCount,
          reason: 'mismatch for ${puzzle.key}');
    }
  });

  test('digits are stored in ascending order', () {
    for (final puzzle in puzzles) {
      final sorted = List.of(puzzle.digits)..sort();
      expect(puzzle.digits, sorted);
    }
  });

  test('the rule block matches the app rules', () {
    final rule = data['rule'] as Map<String, dynamic>;
    expect(rule['target'], 10);
    expect(rule['division'], 'exact');
    expect(rule['negatives'], true);
  });

  test('puzzle keys are unique', () {
    final keys = <String>{};
    for (final puzzle in puzzles) {
      expect(keys.add(puzzle.key), true,
          reason: 'duplicate key: ${puzzle.key}');
    }
    expect(keys, hasLength(548));
  });

  test('each puzzle difficulty matches the derived tier', () {
    final thresholds =
        Thresholds.fromJson(data['thresholds'] as Map<String, dynamic>);
    for (final puzzle in puzzles) {
      final derivedDifficulty =
          difficultyFor(puzzle.solutionCount, thresholds);
      expect(derivedDifficulty, puzzle.difficulty,
          reason: 'mismatch for ${puzzle.key}: expected $derivedDifficulty, '
              'got ${puzzle.difficulty}');
    }
  });

  test(
      'fromJson throws immediately when a digit is not an integer, '
      'rather than deferring the failure', () {
    // Valid JSON, wrong shape: 'd' holds a non-integer. A lazy
    // (json['d'] as List).cast<int>() would let this through fromJson
    // unnoticed and only throw later, deep inside the solver or board.
    final malformed = <String, dynamic>{
      'd': [1, 2, 3, 'x'],
      'n': 1,
      'div': false,
      'lv': 'easy',
    };
    expect(() => Puzzle.fromJson(malformed), throwsA(isA<TypeError>()));
  });
}
