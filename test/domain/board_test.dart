import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/board.dart';
import 'package:make10/domain/operation.dart';

void main() {
  test('initial board holds four cards with distinct ids', () {
    final board = Board.initial([5, 5, 3, 1]);
    expect(board.cards, hasLength(4));
    expect(board.cards.map((c) => c.value).toList(), [5, 5, 3, 1]);
    expect(board.cards.map((c) => c.id).toSet(), hasLength(4));
  });

  test('apply merges two cards into one', () {
    final board = Board.initial([3, 4, 7, 9]);
    final next = board.apply(board.cards[0].id, board.cards[1].id, Op.mul)!;
    expect(next.cards, hasLength(3));
    expect(next.values, contains(12));
  });

  test('apply returns null for a non-exact division', () {
    final board = Board.initial([7, 2, 1, 1]);
    expect(board.apply(board.cards[0].id, board.cards[1].id, Op.div), isNull);
  });

  test('apply returns null for division by zero', () {
    final board = Board.initial([5, 0, 1, 1]);
    expect(board.apply(board.cards[0].id, board.cards[1].id, Op.div), isNull);
  });

  test('apply keeps operand order for subtraction', () {
    final board = Board.initial([3, 8, 1, 1]);
    final next = board.apply(board.cards[0].id, board.cards[1].id, Op.sub)!;
    expect(next.values, contains(-5));
  });

  test('undo restores the previous board', () {
    final board = Board.initial([3, 4, 7, 9]);
    final next = board.apply(board.cards[0].id, board.cards[1].id, Op.mul)!;
    final back = next.undo();
    expect(back.cards.map((c) => c.value).toList(), [3, 4, 7, 9]);
    expect(back.canUndo, isFalse);
  });

  test('undo on the initial board is a no-op', () {
    final board = Board.initial([3, 4, 7, 9]);
    expect(board.undo().values, board.values);
  });

  test('reset returns to the initial four cards after several moves', () {
    var board = Board.initial([3, 4, 7, 9]);
    board = board.apply(board.cards[0].id, board.cards[1].id, Op.mul)!;
    board = board.apply(board.cards[0].id, board.cards[1].id, Op.add)!;
    expect(board.cards, hasLength(2));
    expect(board.reset().values, [3, 4, 7, 9]);
  });

  test('isCleared is true only when one card of value 10 remains', () {
    var board = Board.initial([3, 4, 7, 9]);
    // 3*4=12, 12-9=3, 3+7=10
    board = board.apply(board.cards[0].id, board.cards[1].id, Op.mul)!;
    final twelve = board.cards.firstWhere((c) => c.value == 12);
    final nine = board.cards.firstWhere((c) => c.value == 9);
    board = board.apply(twelve.id, nine.id, Op.sub)!;
    final three = board.cards.firstWhere((c) => c.value == 3);
    final seven = board.cards.firstWhere((c) => c.value == 7);
    board = board.apply(three.id, seven.id, Op.add)!;
    expect(board.isFinished, isTrue);
    expect(board.isCleared, isTrue);
    expect(board.values, [kTarget]);
  });

  test('isFinished without reaching the target is not cleared', () {
    var board = Board.initial([1, 1, 1, 1]);
    board = board.apply(board.cards[0].id, board.cards[1].id, Op.add)!;
    board = board.apply(board.cards[0].id, board.cards[1].id, Op.add)!;
    board = board.apply(board.cards[0].id, board.cards[1].id, Op.add)!;
    expect(board.isFinished, isTrue);
    expect(board.isCleared, isFalse);
  });
}
