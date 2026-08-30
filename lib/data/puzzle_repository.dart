import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/difficulty.dart';
import '../domain/operation.dart';
import '../domain/puzzle.dart';
import 'history_repository.dart';

/// 同梱データが読めない・アプリのルールと食い違うときに投げる。
class PuzzleDataException implements Exception {
  final String message;
  const PuzzleDataException(this.message);

  @override
  String toString() => 'PuzzleDataException: $message';
}

const int _supportedVersion = 1;

class PuzzleRepository {
  final HistoryRepository _history;
  final Random _random;
  final Map<Difficulty, List<Puzzle>> _pools = {};

  PuzzleRepository(this._history, {Random? random})
      : _random = random ?? Random();

  Future<void> loadFromAsset() async {
    final raw = await rootBundle.loadString('assets/puzzles.json');
    await loadFromString(raw);
  }

  Future<void> loadFromString(String raw) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      throw PuzzleDataException('puzzles.json を解析できません: $e');
    }

    if (data['version'] != _supportedVersion) {
      throw PuzzleDataException(
          'puzzles.json のバージョンが未対応です: ${data['version']}');
    }

    final rule = data['rule'];
    if (rule is! Map<String, dynamic> ||
        rule['target'] != kTarget ||
        rule['division'] != 'exact' ||
        rule['negatives'] != true) {
      throw PuzzleDataException(
          'puzzles.json のルールがアプリのルールと一致しません: $rule');
    }

    final list = data['puzzles'];
    if (list is! List || list.isEmpty) {
      throw PuzzleDataException('puzzles.json に問題が入っていません');
    }

    final pools = <Difficulty, List<Puzzle>>{};
    for (final entry in list) {
      final puzzle = Puzzle.fromJson(entry as Map<String, dynamic>);
      pools.putIfAbsent(puzzle.difficulty, () => <Puzzle>[]).add(puzzle);
    }

    for (final difficulty in Difficulty.values) {
      if ((pools[difficulty] ?? const <Puzzle>[]).isEmpty) {
        throw PuzzleDataException('${difficulty.key} の問題がありません');
      }
    }

    // ここまで到達すれば全検証を通過している。_pools の更新はここでまとめて
    // 行うことで、途中で例外が飛んだ場合に _pools が呼び出し前の状態のまま
    // 残ることを保証する（中途半端なプールで next() を動かさないため）。
    _pools
      ..clear()
      ..addAll(pools);
  }

  /// 直近の履歴に無い問題を 1 問返し、履歴に記録する。
  ///
  /// 履歴の除外で候補が尽きることはない（最小プール 172 問に対し履歴は 50 件）
  /// が、データを差し替えた場合に備えて空になったら履歴を無視して抽選する。
  Puzzle next(Difficulty difficulty) {
    final pool = _pools[difficulty];
    if (pool == null) {
      throw const PuzzleDataException('パズルデータが読み込まれていません');
    }
    final recent = _history.recent(difficulty).toSet();
    final candidates =
        pool.where((p) => !recent.contains(p.key)).toList(growable: false);
    final source = candidates.isEmpty ? pool : candidates;
    final puzzle = source[_random.nextInt(source.length)];
    _history.record(difficulty, puzzle.key);
    return puzzle;
  }
}
