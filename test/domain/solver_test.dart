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
    final canonicals = solve([0, 0, 3, 7]).map((s) => s.canonical).toList();
    expect(canonicals.toSet().length, canonicals.length);
  });

  test('input order does not change the solution count', () {
    expect(solve([9, 2, 0, 2]).length, solve([0, 2, 2, 9]).length);
  });
}
