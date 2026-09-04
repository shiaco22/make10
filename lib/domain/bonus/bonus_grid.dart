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
