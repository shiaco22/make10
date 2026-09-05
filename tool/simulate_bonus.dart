// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:make10/domain/bonus/bonus_grid.dart';

/// ボーナスゲームの実測スクリプト。
///
/// 仕様 §3 の数値は、ルールを別言語で再実装して測ったものである。
/// このスクリプトは**実エンジン(`lib/domain/bonus/`)そのもの**を回して
/// 同じ数値が出るかを確かめる(仕様 §11.5)。ずれた場合は、実エンジンと
/// 仕様のどちらが正しいかを判断して仕様を更新すること。
///
/// `tool/generate_puzzles.dart` と違い、出力物を同梱しないのでビルド手順
/// には組み込まない。補充は実行時の乱数であり、事前計算する表がない。
///
/// 実行:
///   C:/flutter/bin/dart.bat run tool/simulate_bonus.dart

/// 1 回の試行の結果。
class BonusSimRun {
  final int taps;
  final int score;
  final bool won;

  /// 上限を使い切ったあとに詰んでゲームオーバーになったか。
  ///
  /// `won` と同時に true にはならない(`BonusGrid.tap` の `isStuck` は
  /// クリアと排他 — 仕様 §2.4)。どちらも false のまま返るのは、
  /// `_play` の安全弁 `cap`(既定 20000 タップ)に達した場合だけで、
  /// 上限付きのエンジンでは実質起こらないはず。
  final bool gameOver;
  final int repairs;
  final int cellsChanged;
  final int topMoved;

  /// 全並べ替え(`repairIfStuck` の手順 2)へ落ちた回数。
  ///
  /// `BonusMerge.usedFullShuffle`(`BonusRepair.usedFullShuffle` をそのまま
  /// 運んだもの)を直接数えた実測値(仕様 §2.6・§11.5)。
  final int fallbacks;

  const BonusSimRun({
    required this.taps,
    required this.score,
    required this.won,
    required this.gameOver,
    required this.repairs,
    required this.cellsChanged,
    required this.topMoved,
    required this.fallbacks,
  });
}

/// 複数回の試行をまとめた結果。
class BonusSimResult {
  final int runs;
  final int wins;

  /// 上限を使い切って詰んだ(ゲームオーバーになった)試行数。
  ///
  /// `wins + gameOvers == runs` になるはず — 上限付きのエンジンでは
  /// 1 ゲームは必ずクリアかゲームオーバーのどちらかで終わる(仕様 §3.1)。
  final int gameOvers;
  final int tapsP10;

  /// 10 に到達した試行だけで見たタップ数の中央値(仕様 §6「到達時タップ中央」)。
  final double tapsMedian;
  final int tapsP90;

  /// ゲームオーバーになった試行だけで見たタップ数の中央値
  /// (仕様 §6「GO 時タップ中央」)。該当する試行が 0 件なら 0。
  final double goTapsMedian;

  /// 全試行(クリア・ゲームオーバーの両方を含む)で見たスコアの中央値
  /// (仕様 §6「全体スコア中央」)。上限が無かった元仕様 §3.1 の時代は
  /// 全試行がクリアだったので勝者限定の中央値と一致していたが、上限を
  /// 入れた now では「クリアした試行だけ」ではなく「全試行」で見ないと
  /// 仕様 §6 の数値と一致しない。
  final double scoreMedian;
  final double repairsPerRun;
  final double cellsChangedPerRepair;
  final int repairsTopMoved;
  final int fallbacks;

  const BonusSimResult({
    required this.runs,
    required this.wins,
    required this.gameOvers,
    required this.tapsP10,
    required this.tapsMedian,
    required this.tapsP90,
    required this.goTapsMedian,
    required this.scoreMedian,
    required this.repairsPerRun,
    required this.cellsChangedPerRepair,
    required this.repairsTopMoved,
    required this.fallbacks,
  });
}

/// 打てる手の中から [policy] に従って 1 つ選ぶ。
///
/// プレイヤーの方針を 3 通り置くのは、所要タップ数が方針で変わるため。
/// 仕様 §3.1 は 3 通りすべての数値を載せている。
int _choose(BonusGrid grid, List<int> options, String policy) {
  var best = options.first;
  var bestKey = -1.0;
  for (final index in options) {
    final n = grid.cells[index];
    final k = grid.componentAt(index).length;
    final double key;
    switch (policy) {
      case 'climb':
        key = n * 100.0 + k;
      case 'group':
        key = k * 100.0 + n;
      case 'score':
      default:
        key = n * k * 1.0;
    }
    if (key > bestKey) {
      bestKey = key;
      best = index;
    }
  }
  return best;
}

/// 打てる手の添字。同じ連結成分は代表 1 つだけを返す
/// (同じ成分ならどのマスを押しても点数は同じなので、方針の比較で
/// 重複して数える意味がない)。
List<int> _legalTaps(BonusGrid grid) {
  final seen = <int>{};
  final out = <int>[];
  for (var i = 0; i < kBonusCells; i++) {
    if (seen.contains(i)) continue;
    final component = grid.componentAt(i);
    seen.addAll(component);
    if (component.length >= 2) out.add(i);
  }
  return out;
}

BonusSimRun _play(Random random, String policy, {int cap = 20000}) {
  var grid = BonusGrid.deal(random);
  var score = 0;
  var taps = 0;
  var repairs = 0;
  var cellsChanged = 0;
  var topMoved = 0;
  var fallbacks = 0;

  while (taps < cap) {
    final options = _legalTaps(grid);
    if (options.isEmpty) {
      // tap() が必ず修復済みの盤面を返すので、ここには来ないはず。
      // 来たら実エンジンの不変条件が壊れている。
      throw StateError('打てる手が無い盤面が返された: ${grid.cells}');
    }
    final index = _choose(grid, options, policy);

    // 修復が「最大値のマスを動かしていないか」を見るための、タップ前の
    // 状態。タップ後の盤面（重力・補充・修復を経た後）から見るのでは
    // 判定できない — maxValue はその時点で実際に盤面にある値をそのまま
    // 返すので、「タップ後の最大値が topBefore と一致する」ことを条件に
    // 「topBefore のマスがまだ存在するか」を調べても、前者が成り立つ時点で
    // 後者は定義上つねに真になり、修復が本当にマスを消し去っていても
    // 検出できない（常に 0 を返す壊れた判定になる）。ここでは代わりに、
    // タップ前の値で「このタップ自身が最大値の成分を消費したか」を判定し、
    // 消費していない場合に限って、タップ後に topBefore の値が 1 つも
    // 残っていないかを見る。重力・補充は既存セルの値を変えない
    // (位置を動かす・空きを埋めるだけ)ので、タップが最大値に触れていない
    // 限り、topBefore の消滅は修復の仕業だと言える。
    final topBefore = grid.maxValue;
    final tappedValue = grid.cells[index];
    final topCountBefore = grid.cells.where((v) => v == topBefore).length;

    // セッション(BonusSession.tap)と同じ規則: 残り(上限 - 使用済み)が
    // 無くなったら修復を断る(仕様 §2.4)。断った結果詰んでいれば
    // `merge.isStuck` が true になり、その手でゲームオーバーが確定する。
    final merge =
        grid.tap(index, random, repairIfStuck: repairs < kBonusRepairLimit)!;
    score += merge.gained;
    taps++;

    if (merge.repairedCells > 0) {
      // isStuck の手は修復していない(修復を断った結果なので)。ここで
      // 数えれば「修復が起きた回数」だけを数えることになり、
      // isStuck とは排他になる。
      repairs++;
      cellsChanged += merge.repairedCells;
      if (merge.usedFullShuffle) fallbacks++;
      // タップした成分自体が最大値だった場合、それが消えるのは修復では
      // なくマージ自身の仕業なので比較の対象から外す。
      if (!merge.cleared && tappedValue != topBefore) {
        final topCountAfter =
            merge.grid.cells.where((v) => v == topBefore).length;
        if (topCountAfter == 0 && topCountBefore > 0) {
          topMoved++;
        }
      }
    }

    if (merge.cleared) {
      return BonusSimRun(
        taps: taps,
        score: score,
        won: true,
        gameOver: false,
        repairs: repairs,
        cellsChanged: cellsChanged,
        topMoved: topMoved,
        fallbacks: fallbacks,
      );
    }

    if (merge.isStuck) {
      // 打った手自体のスコアは加算済み(仕様 §3.1: 「打った手のスコアは
      // 加算する」)。ここで終える。
      return BonusSimRun(
        taps: taps,
        score: score,
        won: false,
        gameOver: true,
        repairs: repairs,
        cellsChanged: cellsChanged,
        topMoved: topMoved,
        fallbacks: fallbacks,
      );
    }
    grid = merge.grid;
  }

  return BonusSimRun(
    taps: taps,
    score: score,
    won: false,
    gameOver: false,
    repairs: repairs,
    cellsChanged: cellsChanged,
    topMoved: topMoved,
    fallbacks: fallbacks,
  );
}

int _percentile(List<int> sorted, double q) {
  if (sorted.isEmpty) return 0;
  final i = (sorted.length * q).floor();
  return sorted[i >= sorted.length ? sorted.length - 1 : i];
}

double _median(List<int> sorted) {
  if (sorted.isEmpty) return 0;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

BonusSimResult simulate({
  required int runs,
  required int seed,
  required String policy,
}) {
  final random = Random(seed);
  final results = [for (var i = 0; i < runs; i++) _play(random, policy)];
  final wins = results.where((r) => r.won).toList();
  final gameOvers = results.where((r) => r.gameOver).toList();
  final taps = [for (final r in wins) r.taps]..sort();
  final goTaps = [for (final r in gameOvers) r.taps]..sort();
  // 全試行(クリア・ゲームオーバーの両方)のスコア。仕様 §6「全体スコア
  // 中央」は上限を入れたことで「クリアした試行だけ」とは一致しなくなった
  // (このファイル冒頭の BonusSimResult.scoreMedian のコメント参照)。
  final scores = [for (final r in results) r.score]..sort();
  final totalRepairs = results.fold(0, (a, r) => a + r.repairs);
  final totalChanged = results.fold(0, (a, r) => a + r.cellsChanged);

  return BonusSimResult(
    runs: runs,
    wins: wins.length,
    gameOvers: gameOvers.length,
    tapsP10: _percentile(taps, 0.10),
    tapsMedian: _median(taps),
    tapsP90: _percentile(taps, 0.90),
    goTapsMedian: _median(goTaps),
    scoreMedian: _median(scores),
    repairsPerRun: totalRepairs / runs,
    cellsChangedPerRepair:
        totalRepairs == 0 ? 0 : totalChanged / totalRepairs,
    repairsTopMoved: results.fold(0, (a, r) => a + r.topMoved),
    fallbacks: results.fold(0, (a, r) => a + r.fallbacks),
  );
}

void main(List<String> args) {
  final runs = args.isNotEmpty ? int.parse(args[0]) : 300;
  final seed = args.length > 1 ? int.parse(args[1]) : 20260903;

  print('runs=$runs seed=$seed  '
      '(仕様 §6 との突き合わせ、入れ替え上限 $kBonusRepairLimit 回)');
  print('');
  print('policy   10到達率  到達時中央  GO時中央  全体スコア中央');
  for (final policy in ['score', 'climb', 'group']) {
    final r = simulate(runs: runs, seed: seed, policy: policy);
    final winRate = r.wins / r.runs * 100;
    print('${policy.padRight(8)}'
        '${'${winRate.toStringAsFixed(1)}%'.padLeft(8)}'
        '${r.tapsMedian.toStringAsFixed(0).padLeft(12)}'
        '${r.goTapsMedian.toStringAsFixed(0).padLeft(10)}'
        '${r.scoreMedian.toStringAsFixed(0).padLeft(16)}');
  }

  print('');
  final scoreRun = simulate(runs: runs, seed: seed, policy: 'score');
  print('詰みの修復 (policy=score):');
  print('  1 ゲームあたり        : ${scoreRun.repairsPerRun.toStringAsFixed(1)} 回');
  print('  1 回で書き換わるマス数: '
      '${scoreRun.cellsChangedPerRepair.toStringAsFixed(1)}');
  print('  最大値のマスが消えた  : ${scoreRun.repairsTopMoved} 回');
  print('  全並べ替えへの落下    : ${scoreRun.fallbacks} 回');

  // 上限付きのエンジンでは「必ず 10 に到達する」はもう成り立たない
  // (仕様 §6)。その代わり、1 ゲームは必ずクリアかゲームオーバーの
  // どちらかで終わるはず — `_play` の安全弁 `cap`(既定 20000 タップ)に
  // 達した試行が 1 つでもあれば実エンジンの不変条件が壊れている。
  if (scoreRun.wins + scoreRun.gameOvers != scoreRun.runs) {
    stderr.writeln('勝ちでもゲームオーバーでもない試行があった'
        '(ループの安全弁 cap に達した可能性): '
        '${scoreRun.runs - scoreRun.wins - scoreRun.gameOvers} '
        '/ ${scoreRun.runs}');
    exit(1);
  }
}
