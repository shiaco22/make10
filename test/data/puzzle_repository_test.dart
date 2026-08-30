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

  // 実データのコピーを 1 件だけ壊した JSON を作る。index は 3 難易度すべてが
  // 出現し終えた後（実データは先頭 15 件で揃う）を指定すれば、非アトミックな
  // 実装は「空ではないが末尾が欠けた」プールを残してしまう状況を再現できる。
  String brokenAtIndex(int index) {
    final decoded = jsonDecode(realAsset) as Map<String, dynamic>;
    final puzzles = decoded['puzzles'] as List;
    final entry =
        Map<String, dynamic>.from(puzzles[index] as Map<String, dynamic>);
    entry['d'] = 'not-a-list'; // Puzzle.fromJson が List キャストで失敗する。
    puzzles[index] = entry;
    return jsonEncode(decoded);
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

  test('keeps the pools intact when a later load fails (atomicity)',
      () async {
    final repo = await repoWith(realAsset);

    // index 300 より前で 3 難易度とも複数件たまっている（易 123 / 難 66 / 普 111）。
    // 非アトミックな実装だと、この失敗後も _pools は空にはならず、この時点までの
    // 断片だけが残ってしまう。
    await expectLater(
      repo.loadFromString(brokenAtIndex(300)),
      throwsA(anything),
    );

    // 失敗した読み込みが _pools を壊していないことは、非空チェックだけでは
    // 検出できない（欠けたプールも非空ではある）。そこで、同じシードで実データ
    // だけを読み込んだ基準リポジトリと抽選結果を突き合わせる。プールが欠けたり
    // 順序がずれたりしていれば、candidates / nextInt の分岐先が変わってすぐに
    // 結果が食い違うはずなので、これは「例外が飛ばない」より強い検証になる。
    final reference = await repoWith(realAsset);
    for (var i = 0; i < 600; i++) {
      for (final difficulty in Difficulty.values) {
        expect(
          repo.next(difficulty).key,
          reference.next(difficulty).key,
          reason: 'diverged at draw $i for $difficulty',
        );
      }
    }
  });

  test(
      'throws PuzzleDataException from next() when no load has succeeded '
      'yet (not a null-check error)', () async {
    final history = HistoryRepository();
    await history.load();
    final repo = PuzzleRepository(history, random: Random(42));

    // コールドな（一度も成功していない）リポジトリでも失敗した読み込みは
    // _pools を汚さないことを確認したうえで、next() の例外の型を検証する。
    await expectLater(
      repo.loadFromString(brokenAtIndex(300)),
      throwsA(anything),
    );

    expect(
      () => repo.next(Difficulty.easy),
      throwsA(isA<PuzzleDataException>()),
    );
  });
}
