import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/operation.dart';

void main() {
  test('kTarget is 10', () {
    expect(kTarget, 10);
  });

  test('addition, subtraction, multiplication', () {
    expect(applyOp(3, 4, Op.add), 7);
    expect(applyOp(3, 4, Op.sub), -1);
    expect(applyOp(3, 4, Op.mul), 12);
  });

  test('negative intermediate values are allowed', () {
    expect(applyOp(3, 8, Op.sub), -5);
  });

  test('division must be exact', () {
    expect(applyOp(6, 3, Op.div), 2);
    expect(applyOp(7, 2, Op.div), isNull);
  });

  test('division by zero is rejected', () {
    expect(applyOp(5, 0, Op.div), isNull);
  });

  test('exact division works with negative operands', () {
    expect(applyOp(-8, 4, Op.div), -2);
    expect(applyOp(8, -4, Op.div), -2);
    expect(applyOp(-6, 4, Op.div), isNull);
  });

  test('opSymbol renders display characters', () {
    expect(opSymbol(Op.add), '+');
    expect(opSymbol(Op.sub), '-');
    expect(opSymbol(Op.mul), '×');
    expect(opSymbol(Op.div), '÷');
  });
}
