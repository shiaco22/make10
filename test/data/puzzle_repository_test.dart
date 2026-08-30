import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/history_repository.dart';
import 'package:make10/data/puzzle_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:shared_preferences/shared_preferences.dart';

String get realAsset => File('assets/puzzles.json').readAsStringSync();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PuzzleRepository> repoWith(String json) async {
    final history = HistoryRepository();
    await history.load();
    final repo = PuzzleRepository(history, random: Random(42));
    await repo.loadFromString(json);
    return repo;
  }

  test('loads the real asset and pools every difficulty', () async {
    final repo = await repoWith(realAsset);
    for (final difficulty in Difficulty.values) {
      expect(repo.next(difficulty).difficulty, difficulty);
    }
  });

  // 非同期の失敗は expectLater に Future を渡して待つ。
  // expect(() => future, throwsA(...)) は Future を待たないので素通りする。
  test('rejects a version it does not understand', () async {
    final json = jsonDecode(realAsset) as Map<String, dynamic>;
    json['version'] = 99;
    await expectLater(
      repoWith(jsonEncode(json)),
      throwsA(isA<PuzzleDataException>()),
    );
  });

  test('rejects a rule block that disagrees with the app', () async {
    final json = jsonDecode(realAsset) as Map<String, dynamic>;
    (json['rule'] as Map<String, dynamic>)['division'] = 'fractional';
    await expectLater(
      repoWith(jsonEncode(json)),
      throwsA(isA<PuzzleDataException>()),
    );
  });

  test('rejects malformed json', () async {
    await expectLater(
      repoWith('{not json'),
      throwsA(isA<PuzzleDataException>()),
    );
  });

  test('does not repeat a puzzle within the history window', () async {
    final repo = await repoWith(realAsset);
    final seen = <String>{};
    for (var i = 0; i < kHistoryLimit; i++) {
      final puzzle = repo.next(Difficulty.hard);
      expect(seen.contains(puzzle.key), isFalse,
          reason: 'repeated ${puzzle.key} at draw $i');
      seen.add(puzzle.key);
    }
  });

  test('keeps drawing past the history window without running dry', () async {
    final repo = await repoWith(realAsset);
    for (var i = 0; i < kHistoryLimit * 4; i++) {
      expect(repo.next(Difficulty.hard).difficulty, Difficulty.hard);
    }
  });

  test('records every drawn puzzle in the shared history', () async {
    final history = HistoryRepository();
    await history.load();
    final repo = PuzzleRepository(history, random: Random(1));
    await repo.loadFromString(realAsset);
    final puzzle = repo.next(Difficulty.normal);
    expect(history.recent(Difficulty.normal), contains(puzzle.key));
  });
}
