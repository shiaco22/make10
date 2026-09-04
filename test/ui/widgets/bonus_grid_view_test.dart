import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid distinctGrid() => gridOf([
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 1],
      [2, 3, 4, 5, 6],
      [7, 8, 9, 1, 2],
      [3, 4, 5, 6, 7],
    ]);

Future<void> pumpGrid(
  WidgetTester tester,
  BonusGrid grid, {
  required void Function(int) onTapCell,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: BonusGridView(grid: grid, onTapCell: onTapCell)),
      ),
    ),
  );
}

void main() {
  testWidgets('25 マスすべてを描く', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {});
    // 値 9 は 2 箇所、値 1 は 3 箇所にある。総数で数える。
    expect(find.byType(BonusCellTile), findsNWidgets(kBonusCells));
  });

  testWidgets('マスの数字を表示する', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {});
    expect(find.text('7'), findsNWidgets(3));
    expect(find.text('8'), findsNWidgets(2));
  });

  testWidgets('タップした添字を通知する', (tester) async {
    final tapped = <int>[];
    await pumpGrid(tester, distinctGrid(), onTapCell: tapped.add);
    await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
    await tester.tap(find.byKey(const ValueKey('bonus-cell-24')));
    await tester.tap(find.byKey(const ValueKey('bonus-cell-12')));
    expect(tapped, [0, 24, 12]);
  });

  testWidgets('320pt 幅でも 25 マスすべてがタップできる', (tester) async {
    // 既存 GameScreen で、固定サイズのカードが狭い画面で 2 行に折り返し、
    // 4 枚目がヒットテストに反応しなくなった不具合と同じ罠を防ぐ。
    // Wrap は溢れてもエラーを出さないので、テストで押せることを直接見る。
    final tapped = <int>[];
    await pumpGrid(
      tester,
      distinctGrid(),
      onTapCell: tapped.add,
      size: const Size(320, 480),
    );
    expect(tester.takeException(), isNull);
    for (var i = 0; i < kBonusCells; i++) {
      await tester.tap(find.byKey(ValueKey('bonus-cell-$i')));
    }
    expect(tapped, [for (var i = 0; i < kBonusCells; i++) i],
        reason: '320pt 幅で押せないマスがある');
  });

  testWidgets('盤面は正方形で、横に溢れない', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {},
        size: const Size(320, 480));
    final box = tester.getSize(find.byType(BonusGridView));
    expect(box.width, closeTo(box.height, 1.0), reason: '盤面が正方形でない');
    expect(box.width, lessThanOrEqualTo(320));
  });

  testWidgets('横長の画面でも高さに収まる', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {},
        size: const Size(800, 360));
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byType(BonusGridView));
    expect(box.height, lessThanOrEqualTo(360));
  });

  testWidgets('10 のマスが他と区別して描かれる', (tester) async {
    final cleared = gridOf([
      [kBonusTarget, 1, 2, 3, 4],
      [5, 6, 7, 8, 9],
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 1],
      [2, 3, 4, 5, 6],
    ]);
    await pumpGrid(tester, cleared, onTapCell: (_) {});
    expect(find.text('10'), findsOneWidget);
  });
}
