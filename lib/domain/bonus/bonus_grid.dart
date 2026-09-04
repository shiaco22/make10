import 'dart:math';

import 'spawn_rule.dart';

/// 盤面の一辺のマス数。
const int kBonusSize = 5;

/// 盤面のマス数。
const int kBonusCells = kBonusSize * kBonusSize;

/// このボーナスゲームの目標値。
const int kBonusTarget = 10;

/// 空きマスを表す値。
///
/// 1 手の途中(マージ直後から補充までの間)にだけ現れる内部状態で、
/// プレイヤーには見えない。0 は正規の値 1..10 より小さいので、
/// [BonusGrid.maxValue] は空きを特別扱いせずに最大値を取れる。
const int kBonusEmpty = 0;

/// 添字 [i] の上下左右の添字。
///
/// 添字が隣(4 と 5 など)でも行が変われば盤面上では隣接しないため、
/// 列の端をまたがないよう row/col に戻して判定する。1 手ごとに
/// 塗り広げで何度も引くので、起動時に 1 度だけ作って使い回す。
final List<List<int>> _neighbors = List.generate(kBonusCells, (i) {
  final row = i ~/ kBonusSize;
  final col = i % kBonusSize;
  return <int>[
    if (row > 0) i - kBonusSize,
    if (row < kBonusSize - 1) i + kBonusSize,
    if (col > 0) i - 1,
    if (col < kBonusSize - 1) i + 1,
  ];
});

/// ボーナスゲームの盤面。イミュータブルで、1 手ごとに新しい盤面を返す
/// (既存 `Board` と同じ流儀)。
class BonusGrid {
  final List<int> cells;

  BonusGrid._(List<int> cells) : cells = List.unmodifiable(cells);

  /// 長さ [kBonusCells] のリストから作る。row-major(添字 = row * 5 + col)。
  factory BonusGrid.of(List<int> cells) {
    if (cells.length != kBonusCells) {
      throw ArgumentError.value(
        cells.length,
        'cells.length',
        '盤面は $kBonusCells マスでなければならない',
      );
    }
    return BonusGrid._(List<int>.of(cells));
  }

  int valueAt(int row, int col) => cells[row * kBonusSize + col];

  /// 盤面の最大値。空きマス([kBonusEmpty])は 0 なので結果に影響しない。
  int get maxValue => cells.reduce((a, b) => a > b ? a : b);

  /// [index] から上下左右に連結する同値マスの集合([index] 自身を含む)。
  Set<int> componentAt(int index) {
    final value = cells[index];
    final seen = <int>{index};
    final stack = <int>[index];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      for (final j in _neighbors[i]) {
        if (cells[j] == value && seen.add(j)) {
          stack.add(j);
        }
      }
    }
    return seen;
  }

  /// [index] をタップできるか。同値の隣接が 1 つも無ければ打てない。
  bool canTap(int index) => componentAt(index).length >= 2;

  /// [index] をタップした結果を返す。ルール上打てない手なら null
  /// (盤面は一切変化しない — 既存 `Board.apply` と同じ契約)。
  ///
  /// [random] は補充に使う。盤面自体は不変なので、乱数は呼び出しごとに
  /// 外から渡す(`PuzzleRepository` と同じ、注入して再現可能にする流儀)。
  BonusMerge? tap(int index, Random random) {
    final component = componentAt(index);
    if (component.length < 2) return null;

    final value = cells[index];
    final count = component.length;
    final next = List<int>.of(cells);
    for (final i in component) {
      next[i] = kBonusEmpty;
    }
    next[index] = value + 1;

    if (value + 1 >= kBonusTarget) {
      // クリア時は重力も補充も走らせない。作った 10 が見えている盤面のまま
      // 結果画面に進むため(仕様 §2.5)。空きマスが残るが、この盤面から
      // 次の手を打つことはない。
      return BonusMerge(
        grid: BonusGrid._(next),
        gained: value * count,
        mergedValue: value,
        mergedCount: count,
        cleared: true,
      );
    }

    _applyGravity(next);
    // 補充に使う最大値は「重力の直後・補充の前」に 1 度だけ決め、補充中は
    // 更新しない(仕様 §2.4)。1 手のあいだ補充の分布が揺れないようにする。
    final boardMax = next.reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < kBonusCells; i++) {
      if (next[i] == kBonusEmpty) {
        next[i] = spawnValue(boardMax, random);
      }
    }

    return BonusMerge(
      grid: BonusGrid._(next),
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
    );
  }

  /// 盤面のどこかに合法手があるか。
  ///
  /// 連結成分を数える必要はない。同値の隣接が 1 組でもあればそこが合法手
  /// なので、隣接の走査だけで済む(詰み判定は 1 手ごとに走るため、
  /// 塗り広げを 25 回するより安い)。
  bool get hasLegalMove {
    for (var i = 0; i < kBonusCells; i++) {
      for (final j in _neighbors[i]) {
        if (cells[i] == cells[j]) return true;
      }
    }
    return false;
  }
}

/// 1 手の結果。
class BonusMerge {
  /// 手を適用した後の盤面。
  final BonusGrid grid;

  /// この手で得た点数(`mergedValue * mergedCount`)。
  final int gained;

  /// まとめたマスの数字。
  final int mergedValue;

  /// まとめたマスの数(タップしたマス自身を含む)。
  final int mergedCount;

  /// この手で [kBonusTarget] ができたか。
  final bool cleared;

  const BonusMerge({
    required this.grid,
    required this.gained,
    required this.mergedValue,
    required this.mergedCount,
    required this.cleared,
  });
}

/// 列ごとに重力を適用する。空でないマスが順序を保って下端へ落ち、
/// 空きは上端に集まる。[cells] を直接書き換える。
void _applyGravity(List<int> cells) {
  for (var col = 0; col < kBonusSize; col++) {
    var write = kBonusSize - 1;
    for (var row = kBonusSize - 1; row >= 0; row--) {
      final value = cells[row * kBonusSize + col];
      if (value != kBonusEmpty) {
        cells[write * kBonusSize + col] = value;
        write--;
      }
    }
    for (var row = write; row >= 0; row--) {
      cells[row * kBonusSize + col] = kBonusEmpty;
    }
  }
}
