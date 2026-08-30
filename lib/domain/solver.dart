import 'operation.dart';

/// 解の 1 手。表示に使うので位置ではなく値で持つ。
class SolutionStep {
  final int left;
  final int right;
  final Op op;
  final int result;

  const SolutionStep(this.left, this.right, this.op, this.result);

  @override
  String toString() =>
      '$left ${opSymbol(op)} $right = $result';
}

/// 1 つの解。3 手の列と、重複排除に使う正規形キー。
class Solution {
  final List<SolutionStep> steps;
  final String canonical;

  const Solution(this.steps, this.canonical);
}

/// 探索中のノード。値と、可換演算を正規化した式文字列を持つ。
class _Node {
  final int value;
  final String canonical;

  const _Node(this.value, this.canonical);

  factory _Node.leaf(int v) => _Node(v, '$v');
}

/// 正規形キー専用の演算子表記。[opSymbol] は表示用の Unicode 記号
/// （×, ÷）を返すが、canonical は重複排除にしか使わない内部キーなので
/// ASCII 記号で統一する。
String _canonicalSymbol(Op op) {
  switch (op) {
    case Op.add:
      return '+';
    case Op.sub:
      return '-';
    case Op.mul:
      return '*';
    case Op.div:
      return '/';
  }
}

_Node _combine(_Node a, _Node b, Op op, int value) {
  final s = _canonicalSymbol(op);
  if (op == Op.add || op == Op.mul) {
    // 可換演算は子をソートして (3+7) と (7+3) を同一視する。
    final x = a.canonical;
    final y = b.canonical;
    final ordered = x.compareTo(y) <= 0 ? '($x$s$y)' : '($y$s$x)';
    return _Node(value, ordered);
  }
  return _Node(value, '(${a.canonical}$s${b.canonical})');
}

/// [values] から 10 を作る全解を、正規形で重複排除して返す。
///
/// メモ化はしない。多重集合をキーにキャッシュすると異なる部分式が潰れ、
/// 解の本数を誤るため。経路数は 3,888 以下で十分小さい。
List<Solution> solve(List<int> values) {
  final found = <String, Solution>{};
  final steps = <SolutionStep>[];

  void search(List<_Node> nodes) {
    if (nodes.length == 1) {
      if (nodes.single.value == kTarget) {
        found.putIfAbsent(
          nodes.single.canonical,
          () => Solution(List.of(steps), nodes.single.canonical),
        );
      }
      return;
    }
    for (var i = 0; i < nodes.length; i++) {
      for (var j = 0; j < nodes.length; j++) {
        if (i == j) continue;
        for (final op in Op.values) {
          // 可換演算は片方向だけ試せば足りる。
          if ((op == Op.add || op == Op.mul) && i > j) continue;
          final value = applyOp(nodes[i].value, nodes[j].value, op);
          if (value == null) continue;
          final merged = _combine(nodes[i], nodes[j], op, value);
          final rest = <_Node>[
            for (var k = 0; k < nodes.length; k++)
              if (k != i && k != j) nodes[k],
            merged,
          ];
          steps.add(
            SolutionStep(nodes[i].value, nodes[j].value, op, value),
          );
          search(rest);
          steps.removeLast();
        }
      }
    }
  }

  search([for (final v in values) _Node.leaf(v)]);
  return found.values.toList();
}
