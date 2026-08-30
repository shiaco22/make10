/// 作るべき値。仕様上 10 固定。
const int kTarget = 10;

enum Op { add, sub, mul, div }

/// `a op b` を計算する。ルール上実行できない場合は null を返す。
///
/// - 割り切れない除算は不可
/// - 0 での除算は不可
/// - 負数は許可する
int? applyOp(int a, int b, Op op) {
  switch (op) {
    case Op.add:
      return a + b;
    case Op.sub:
      return a - b;
    case Op.mul:
      return a * b;
    case Op.div:
      if (b == 0 || a % b != 0) return null;
      return a ~/ b;
  }
}

String opSymbol(Op op) {
  switch (op) {
    case Op.add:
      return '+';
    case Op.sub:
      return '-';
    case Op.mul:
      return '×';
    case Op.div:
      return '÷';
  }
}
