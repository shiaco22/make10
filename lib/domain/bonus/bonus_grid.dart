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

/// 1 ゲームで盤面を入れ替え(詰み修復)できる回数の上限。
///
/// 上限を使い切った状態で詰んだらゲームオーバー(仕様 §2)。値を 10 に
/// したのは実測から: 10 到達率が 31.0% になり、1 日 1 回のゲームでは
/// 「3 日に 1 回くらい 10 を見られる」水準になる。5 だと 5.5%(18 日に
/// 1 回)で遠すぎ、15 だと 73.2% でほぼ負けなくなる(仕様 §2.2)。
///
/// カウントするのはセッション側([BonusSession])。盤面はそのゲームで
/// 何回修復したかを知らなくてよい。
const int kBonusRepairLimit = 10;

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
  ///
  /// [repairIfStuck] を false にすると、補充後に詰んでいても修復せず、
  /// [BonusMerge.isStuck] を true にして返す。入れ替えの回数を使い切った
  /// セッションだけがこれを渡す(仕様 §2.4)。既定を true にしてあるのは、
  /// 「tap は詰んだ盤面を返さない」という既存の不変条件をそのまま
  /// 生かすため。
  BonusMerge? tap(int index, Random random, {bool repairIfStuck = true}) {
    final component = componentAt(index);
    if (component.length < 2) return null;

    final value = cells[index];
    final count = component.length;
    final removed = {
      for (final i in component)
        if (i != index) i,
    };

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
        removedCells: removed,
        fallenCells: const {},
        spawnedCells: const {},
        mergedInto: index,
      );
    }

    final fallen = _applyGravity(next);
    // 補充に使う最大値は「重力の直後・補充の前」に 1 度だけ決め、補充中は
    // 更新しない(仕様 §2.4)。1 手のあいだ補充の分布が揺れないようにする。
    final boardMax = next.reduce((a, b) => a > b ? a : b);
    final spawned = <int>{};
    for (var i = 0; i < kBonusCells; i++) {
      if (next[i] == kBonusEmpty) {
        next[i] = spawnValue(boardMax, random);
        spawned.add(i);
      }
    }

    // 修復で書き換わったマスも「新しい数字が現れた」ものとして扱う。
    // どのマスが変わったかは BonusRepair が持っていないので、修復の
    // 前後をここで突き合わせる。
    var resulting = BonusGrid._(next);
    var repairedCells = 0;
    var usedFullShuffle = false;
    var isStuck = false;
    if (repairIfStuck) {
      final beforeRepair = List<int>.of(next);
      final repair = resulting.repairIfStuck(random);
      resulting = repair.grid;
      repairedCells = repair.changedCells;
      usedFullShuffle = repair.usedFullShuffle;
      for (var i = 0; i < kBonusCells; i++) {
        if (resulting.cells[i] != beforeRepair[i]) spawned.add(i);
      }
    } else {
      isStuck = !resulting.hasLegalMove;
    }

    return BonusMerge(
      grid: resulting,
      gained: value * count,
      mergedValue: value,
      mergedCount: count,
      cleared: false,
      removedCells: removed,
      fallenCells: fallen,
      spawnedCells: spawned,
      mergedInto: fallen[index] ?? index,
      repairedCells: repairedCells,
      usedFullShuffle: usedFullShuffle,
      isStuck: isStuck,
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
  /// 隣接させる並べ替えが存在する。実測では手順 1 がほぼ常に解決するが
  /// 稀に手順 2 まで落ちる(実測値は仕様 §2.6・§11.5)。引き直しの終了は
  /// 確率に依存するため、保証を運に委ねないよう手順 2 を残している。
  /// どちらの手順で解決したかは返り値の [BonusRepair.usedFullShuffle]
  /// で分かる。
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

    // ここへ到達するのは稀だが(仕様 §11.5)、引き直しの終了は確率に依存
    // するので、必ず成功する手段を最後に置く。
    final shuffled = List<int>.of(next);
    for (var attempt = 0; attempt < 1000; attempt++) {
      shuffled.shuffle(random);
      final candidate = BonusGrid._(shuffled);
      if (candidate.hasLegalMove) {
        return BonusRepair(
          candidate,
          _changedCells(cells, shuffled),
          usedFullShuffle: true,
        );
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

  /// 修復が起きた場合、それが手順 2(盤面全体の並べ替え)まで落ちたか。
  ///
  /// [repairedCells] が 0(修復していない)なら常に false。[BonusGrid.
  /// repairIfStuck] の [BonusRepair.usedFullShuffle] をそのまま運ぶ
  /// (仕様 §2.6)。実測では稀にしか true にならない(仕様 §11.5)。
  final bool usedFullShuffle;

  /// この手で消えたマス。手を打つ**前**の座標系。
  ///
  /// タップしたマス自身は含まない(そのマスは消えずに `n+1` になる)。
  final Set<int> removedCells;

  /// 重力で動いたマス。手を打つ前の添字 → 打った後の添字。
  /// 動かなかったマスは含まない。
  final Map<int, int> fallenCells;

  /// 補充で新しく湧いたマス。手を打った**後**の座標系。
  ///
  /// 詰み修復で書き換わったマスもここに含める。プレイヤーから見れば
  /// 「新しい数字が現れた」ことに変わりはなく、アニメーションの扱いも
  /// 同じでよい。
  final Set<int> spawnedCells;

  /// `n+1` になったマスの、手を打った**後**の位置。
  final int mergedInto;

  /// 修復を断った結果、合法手が無い盤面のまま返ってきたか。
  ///
  /// `tap(..., repairIfStuck: false)` を渡したときにだけ true になりうる。
  /// セッションはこれを見てゲームオーバーを確定する(仕様 §3.1)。
  final bool isStuck;

  const BonusMerge({
    required this.grid,
    required this.gained,
    required this.mergedValue,
    required this.mergedCount,
    required this.cleared,
    required this.removedCells,
    required this.fallenCells,
    required this.spawnedCells,
    required this.mergedInto,
    this.repairedCells = 0,
    this.usedFullShuffle = false,
    this.isStuck = false,
  });
}

/// 列ごとに重力を適用する。空でないマスが順序を保って下端へ落ち、
/// 空きは上端に集まる。[cells] を直接書き換える。
///
/// 動いたマスの「元の添字 → 新しい添字」を返す。動かなかったマスは
/// 含まない。アニメーションがこの対応を必要とするが、**前後の盤面の
/// 差分からは復元できない** — 同じ値のマスが複数あると対応が一意に
/// 決まらないため。ここでは確定しているので、そのまま返す。
Map<int, int> _applyGravity(List<int> cells) {
  final moved = <int, int>{};
  for (var col = 0; col < kBonusSize; col++) {
    var write = kBonusSize - 1;
    for (var row = kBonusSize - 1; row >= 0; row--) {
      final from = row * kBonusSize + col;
      final value = cells[from];
      if (value != kBonusEmpty) {
        final to = write * kBonusSize + col;
        cells[to] = value;
        if (to != from) moved[from] = to;
        write--;
      }
    }
    for (var row = write; row >= 0; row--) {
      cells[row * kBonusSize + col] = kBonusEmpty;
    }
  }
  return moved;
}

/// 詰みの修復結果。
class BonusRepair {
  final BonusGrid grid;

  /// 修復で書き換えたマス数。0 なら詰んでいなかった。
  final int changedCells;

  /// 手順 2(盤面全体の並べ替え)まで落ちて解決したか。
  ///
  /// false は「詰んでいなかった」と「手順 1(低い値からの引き直し)で
  /// 解決した」の両方を含む — [changedCells] が 0 かどうかで区別する。
  /// 手順 1 の終了は確率に依存するため手順 2 を保証として残しており
  /// (仕様 §2.6)、実際にどちらで解決したかを外から確認できるように
  /// このフィールドを公開する。実測では稀にしか true にならない
  /// (仕様 §11.5)。
  final bool usedFullShuffle;

  const BonusRepair(
    this.grid,
    this.changedCells, {
    this.usedFullShuffle = false,
  });
}

int _changedCells(List<int> before, List<int> after) {
  var count = 0;
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) count++;
  }
  return count;
}
