import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/domain/solver.dart';

void main() {
  test('solution counts match the verified reference values', () {
    expect(solve([1, 5, 5, 5]).length, 1);
    expect(solve([1, 1, 1, 4]).length, 1);
    expect(solve([0, 2, 2, 9]).length, 14);
    expect(solve([3, 4, 7, 9]).length, 18);
    expect(solve([0, 1, 2, 8]).length, 96);
  });

  test('unsolvable combinations return no solutions', () {
    expect(solve([1, 1, 1, 1]), isEmpty);
    expect(solve([1, 1, 9, 9]), isEmpty);
  });

  test('the unique solution of 1,5,5,5 uses division', () {
    final solutions = solve([1, 5, 5, 5]);
    expect(solutions, hasLength(1));
    expect(solutions.single.canonical, '(((5/5)+1)*5)');
  });

  test('every solution reaches the target in three steps', () {
    for (final solution in solve([3, 4, 7, 9])) {
      expect(solution.steps, hasLength(3));
      expect(solution.steps.last.result, kTarget);
    }
  });

  test('commutative duplicates are collapsed', () {
    // 3+7 と 7+3 は同一解として 1 本に数える。
    // 0,0,3,7 は 3+7 を含むが、順序違いで本数が二重にならない。
    //
    // solve() は found.values（canonical をキーにした Map）を返すため、
    // 返り値の canonical はどのみち構造的に重複しえない
    // （canonicals.toSet().length == canonicals.length は常に真になる）。
    // それでは正規化そのものは何も検証できていないので、正規化が実際に
    // 効いている（小さい方の被演算子が常に先に来る）ことと、
    // 正規化されていない並び (7+3) が紛れ込んでいないことを直接確認する。
    final canonicals = solve([0, 0, 3, 7]).map((s) => s.canonical).toList();
    expect(canonicals, contains('(((3+7)+0)+0)'));
    expect(
      canonicals.where((c) => c.contains('7+3')),
      isEmpty,
      reason: 'a non-canonical "7+3" ordering would mean two orderings of '
          'the same commutative merge were not collapsed into one entry',
    );
  });

  test('input order does not change the solution count', () {
    expect(solve([9, 2, 0, 2]).length, solve([0, 2, 2, 9]).length);
  });
}
