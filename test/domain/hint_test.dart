import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/domain/solver.dart';

void main() {
  test('hint returns a move that keeps the board solvable', () {
    final move = hint([1, 5, 5, 5]);
    expect(move, isNotNull);
    final applied = applyOp(
      [1, 5, 5, 5][move!.leftIndex],
      [1, 5, 5, 5][move.rightIndex],
      move.op,
    );
    expect(applied, move.result);
  });

  test('hint is deterministic', () {
    final first = hint([3, 4, 7, 9])!;
    for (var i = 0; i < 5; i++) {
      final again = hint([3, 4, 7, 9])!;
      expect(again.leftIndex, first.leftIndex);
      expect(again.rightIndex, first.rightIndex);
      expect(again.op, first.op);
    }
  });

  test('hint indexes into the caller order, not a sorted copy', () {
    // 5,3,5 は 5*3-5 = 10。ソルバーが内部でソートすると
    // インデックスが呼び出し元の並びとずれる。
    const board = [5, 3, 5];
    final move = hint(board)!;
    final left = board[move.leftIndex];
    final right = board[move.rightIndex];
    expect(applyOp(left, right, move.op), move.result);
    expect(move.leftIndex, isNot(move.rightIndex));
  });

  test('hint returns null when the board cannot reach the target', () {
    expect(hint([1, 1, 1, 1]), isNull);
  });

  test('isDeadEnd is false for a cleared single-card board', () {
    // hint は null を返すが詰みではない。両者を同一視してはいけない。
    expect(hint([kTarget]), isNull);
    expect(isDeadEnd([kTarget]), isFalse);
  });

  test('isDeadEnd is true for a finished board that missed the target', () {
    expect(isDeadEnd([7]), isTrue);
  });

  test('isDeadEnd detects a mid-game dead end', () {
    // 3,4,7,9 は解けるが、3*7=21 から 4,9,21 に進むと 10 は作れない。
    //
    // 元の下書きは「3*4=12 から 12,7,9 に進む」例だったが、これは誤り:
    // 12,7,9 は 12+7=19 → 19-9=10 で実際には解けてしまう
    // (これは 3,4,7,9 自体の 18 通りの解の 1 つでもある)。
    // isDeadEnd は hint の実装と同じ _reachable を使う純粋な到達可能性判定
    // なので、この誤りは実装ではなくテストの具体例の側にあった。
    expect(isDeadEnd([3, 4, 7, 9]), isFalse);
    expect(isDeadEnd([4, 9, 21]), isTrue);
  });
}
