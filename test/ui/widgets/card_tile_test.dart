import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/board.dart';
import 'package:make10/ui/widgets/card_tile.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('renders the card value', (tester) async {
    await tester.pumpWidget(wrap(CardTile(
      card: const CardItem(0, 7),
      selected: false,
      highlighted: false,
      onTap: () {},
    )));
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('renders a negative value', (tester) async {
    await tester.pumpWidget(wrap(CardTile(
      card: const CardItem(0, -5),
      selected: false,
      highlighted: false,
      onTap: () {},
    )));
    expect(find.text('-5'), findsOneWidget);
  });

  testWidgets('reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(CardTile(
      card: const CardItem(0, 3),
      selected: false,
      highlighted: false,
      onTap: () => taps++,
    )));
    await tester.tap(find.byType(CardTile));
    expect(taps, 1);
  });
}
