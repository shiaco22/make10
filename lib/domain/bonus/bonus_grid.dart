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

  /// 新しいゲームの初期盤面を配る(仕様 §2.7)。
  ///
  /// 各マスを独立に 1..3 から引く。`spawnValue` に `boardMax = 4` を
  /// 渡すのがその範囲にあたる。
  ///
  /// **`boardMax = 1` で埋めてはいけない。** 補充の範囲は
  /// `1 .. max(1, boardMax - 1)` なので、1 では 25 マス全部が 1 になり、
  /// 最初のタップが 25 マスを一括マージして 2 を 1 個作るだけの退化した
  /// 開幕になる。
  ///
  /// 3 値であれば同値が隣接しない配置(3 彩色に相当する並び)が存在する
  /// ため、配った直後に詰み検査を通す。実測では 300 ゲーム中 0 回しか
  /// 作動しなかったが、検査は 1 回で済み、外した場合は開幕が完全に詰む。
  factory BonusGrid.deal(Random random) {
    final cells = List<int>.generate(kBonusCells, (_) => spawnValue(4, random));
    return BonusGrid._(cells).repairIfStuck(random).grid;
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

    final repair = BonusGrid._(next).repairIfStuck(random);

    return BonusMerge(
      grid: repair.grid,
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
      repairedCells: repair.changedCells,
    );
  }

  /// 詰んでいれば修復した盤面を、詰んでいなければ自分自身を返す。
  ///
  /// 修復は**値が低いマスから順に引き直す**。25 マスすべてを引き直しても
  /// 合法手ができなければ、盤面全体を並べ替える。
  ///
  /// 全並べ替えを既定にしない理由は実測にある(仕様 §3.2)。全並べ替えは
  /// 1 回で 25 マス中 21.2 マスを書き換え、最大値のマスの位置を 99% の
  /// 確率で壊す。詰みは 8 タップに 1 回起きるので、それではプレイヤーが
  /// 積み上げたものが絶えず散らされる。低い値から引き直す方式は 3.0 マス
  /// しか変えず、最大値のマスは一度も動かなかった。
  ///
  /// 最後の全並べ替えは必ず成功する。25 マスに対して値は 10 種類以下
  /// なので鳩の巣原理により必ず重複があり、重複がある限りそれらを
  /// 隣接させる並べ替えが存在する。実測では 300 ゲーム・3,965 回の修復で
  /// ここへ到達した回数は 0 回だったが、引き直しの終了は確率に依存する
  /// ため、保証を運に委ねないよう残している。
  BonusRepair repairIfStuck(Random random) {
    if (hasLegalMove) return BonusRepair(this, 0);

    final next = List<int>.of(cells);
    final boardMax = maxValue;
    // 値が低い順。同値のマスの間の順序は乱数で散らし、毎回同じ隅から
    // 引き直して偏るのを避ける。タイブレークは `List.sort` に渡す前に
    // 1 度だけ引いた乱数の並べ替えを使う — `compare` の中で毎回
    // `random.nextInt` を引いて符号を返すと、同じ 2 要素の比較結果が
    // 呼び出しのたびに変わり得る(比較関数の一貫性が壊れる)。
    // `List.sort` は一貫性のない比較関数に対する結果を保証しないため、
    // 値の昇順が崩れる恐れがある。
    final tiebreak = List<int>.generate(kBonusCells, (i) => i)..shuffle(random);
    final order = List<int>.generate(kBonusCells, (i) => i)
      ..sort((a, b) {
        final byValue = cells[a].compareTo(cells[b]);
        return byValue != 0 ? byValue : tiebreak[a].compareTo(tiebreak[b]);
      });

    for (final i in order) {
      next[i] = spawnValue(boardMax, random);
      final candidate = BonusGrid._(next);
      if (candidate.hasLegalMove) {
        return BonusRepair(candidate, _changedCells(cells, next));
      }
    }

    // ここへは実測で一度も到達していないが、引き直しの終了は確率に依存
    // するので、必ず成功する手段を最後に置く。
    final shuffled = List<int>.of(next);
    for (var attempt = 0; attempt < 1000; attempt++) {
      shuffled.shuffle(random);
      final candidate = BonusGrid._(shuffled);
      if (candidate.hasLegalMove) {
        return BonusRepair(candidate, _changedCells(cells, shuffled));
      }
    }
    throw StateError('盤面の修復に失敗した: $cells');
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

  /// この手の補充後に詰みを修復して書き換えたマス数。0 なら修復していない。
  ///
  /// 詰みは 1 ゲームに 13 回、およそ 8 タップに 1 回起きる(仕様 §3.2)。
  /// 無言で盤面を書き換えると理不尽に見えるので、UI が通知を出せるように
  /// 手の結果として返す。
  final int repairedCells;

  const BonusMerge({
    required this.grid,
    required this.gained,
    required this.mergedValue,
    required this.mergedCount,
    required this.cleared,
    this.repairedCells = 0,
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

/// 詰みの修復結果。
class BonusRepair {
  final BonusGrid grid;

  /// 修復で書き換えたマス数。0 なら詰んでいなかった。
  final int changedCells;

  const BonusRepair(this.grid, this.changedCells);
}

int _changedCells(List<int> before, List<int> after) {
  var count = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) count++;
  }
  return count;
}
