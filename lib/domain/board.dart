import 'operation.dart';

/// 盤面上の 1 枚。値が同じカードを区別するため id を持つ。
class CardItem {
  final int id;
  final int value;

  const CardItem(this.id, this.value);
}

/// 盤面に適用済みの手。カードを id で指す。
class Move {
  final int leftId;
  final int rightId;
  final Op op;
  final CardItem produced;

  const Move(this.leftId, this.rightId, this.op, this.produced);
}

/// 盤面。イミュータブルで、操作するたびに新しい Board を返す。
class Board {
  final List<int> digits;
  final List<CardItem> cards;
  final List<Move> history;
  final int _nextId;

  /// 呼び出し側が要素を書き換えられないよう、各リストは構築時に
  /// unmodifiable なビューとして保持する。
  Board._(
    List<int> digits,
    List<CardItem> cards,
    List<Move> history,
    this._nextId,
  )   : digits = List.unmodifiable(digits),
        cards = List.unmodifiable(cards),
        history = List.unmodifiable(history);

  factory Board.initial(List<int> digits) {
    final cards = <CardItem>[
      for (var i = 0; i < digits.length; i++) CardItem(i, digits[i]),
    ];
    return Board._(List.of(digits), cards, <Move>[], digits.length);
  }

  List<int> get values => [for (final c in cards) c.value];

  bool get isFinished => cards.length == 1;

  bool get isCleared => cards.length == 1 && cards.single.value == kTarget;

  bool get canUndo => history.isNotEmpty;

  CardItem? cardById(int id) {
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// `left op right` を適用した新しい盤面を返す。
  /// ルール上実行できない場合は null（盤面は変化しない）。
  Board? apply(int leftId, int rightId, Op op) {
    if (leftId == rightId) return null;
    final left = cardById(leftId);
    final right = cardById(rightId);
    if (left == null || right == null) return null;

    final value = applyOp(left.value, right.value, op);
    if (value == null) return null;

    final produced = CardItem(_nextId, value);
    final next = <CardItem>[
      for (final c in cards)
        if (c.id != leftId && c.id != rightId) c,
      produced,
    ];
    return Board._(
      digits,
      next,
      [...history, Move(leftId, rightId, op, produced)],
      _nextId + 1,
    );
  }

  /// 直前の 1 手を取り消す。履歴が空なら自分自身を返す。
  Board undo() {
    if (history.isEmpty) return this;
    var board = Board.initial(digits);
    for (final move in history.sublist(0, history.length - 1)) {
      board = board.apply(move.leftId, move.rightId, move.op)!;
    }
    return board;
  }

  /// 初期の 4 枚に戻す。
  Board reset() => Board.initial(digits);
}
