import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/board.dart';
import 'package:make10/ui/widgets/card_tile.dart';

/// WCAG relative luminance (sRGB), used to compute contrast ratios below.
double _relativeLuminance(Color color) {
  double channel(double c) {
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG contrast ratio between two colors (1.0 = indistinguishable, 21.0 = max).
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a) + 0.05;
  final lb = _relativeLuminance(b) + 0.05;
  return la > lb ? la / lb : lb / la;
}

void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: Center(child: child)),
      );

  /// The actually-painted decoration for the [DecoratedBox] found under the
  /// [CardTile] tagged with [key]. Reading this (rather than
  /// `AnimatedContainer.decoration`, which is always the declarative target)
  /// is what catches a decoration that is still mid-animation.
  BoxDecoration decorationFor(WidgetTester tester, String key) {
    final tile = find.byKey(ValueKey<String>(key));
    final decoratedBoxFinder =
        find.descendant(of: tile, matching: find.byType(DecoratedBox));
    expect(decoratedBoxFinder, findsOneWidget);
    final box = tester.widget<DecoratedBox>(decoratedBoxFinder);
    return box.decoration as BoxDecoration;
  }

  Color borderColorOf(BoxDecoration decoration) =>
      (decoration.border as Border).top.color;

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

  testWidgets(
    'exposes a single accessibility label, not doubled with the '
    "inner Text's own generated label",
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(CardTile(
        card: const CardItem(0, 9),
        selected: false,
        highlighted: false,
        onTap: () {},
      )));

      expect(
        tester.getSemantics(find.byType(CardTile)),
        matchesSemantics(
          label: 'カード 9',
          isButton: true,
          hasTapAction: true,
        ),
      );

      handle.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'normal, selected, highlighted and selected+highlighted paint '
      'distinguishable, contrasting colors ($brightness)',
      (tester) async {
        const card = CardItem(0, 9);
        await tester.pumpWidget(wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CardTile(
                key: const ValueKey('normal'),
                card: card,
                selected: false,
                highlighted: false,
                onTap: () {},
              ),
              CardTile(
                key: const ValueKey('selected'),
                card: card,
                selected: true,
                highlighted: false,
                onTap: () {},
              ),
              CardTile(
                key: const ValueKey('highlighted'),
                card: card,
                selected: false,
                highlighted: true,
                onTap: () {},
              ),
              CardTile(
                key: const ValueKey('both'),
                card: card,
                selected: true,
                highlighted: true,
                onTap: () {},
              ),
            ],
          ),
          brightness: brightness,
        ));

        final theme =
            Theme.of(tester.element(find.byKey(const ValueKey('normal'))));
        final scheme = theme.colorScheme;

        final normal = decorationFor(tester, 'normal');
        final selected = decorationFor(tester, 'selected');
        final highlighted = decorationFor(tester, 'highlighted');
        final both = decorationFor(tester, 'both');

        // Fills: normal, selected and highlighted must each be visually
        // distinct from one another.
        expect(normal.color, theme.cardColor);
        expect(selected.color, scheme.primary);
        expect(highlighted.color, scheme.tertiaryContainer);
        expect(
          {normal.color, selected.color, highlighted.color},
          hasLength(3),
          reason: 'normal, selected and highlighted must paint distinct fills',
        );

        // Combined state intentionally shares its fill with plain
        // "selected" -- selected wins the fill -- so it is distinguished
        // from plain "selected" by its border instead.
        expect(both.color, selected.color);

        expect(borderColorOf(normal), Colors.transparent);
        expect(borderColorOf(selected), Colors.transparent);
        expect(borderColorOf(highlighted), scheme.tertiary);

        final combinedBorder = borderColorOf(both);
        expect(
          combinedBorder,
          isNot(Colors.transparent),
          reason: 'a highlighted+selected card must still show a hint border',
        );
        expect(
          combinedBorder,
          isNot(both.color),
          reason: 'the border must not be painted the same color as the fill',
        );
        expect(
          _contrastRatio(combinedBorder, both.color!),
          greaterThan(3.0),
          reason: 'the hint border must stay visible against whatever fill '
              'is actually painted when both selected and highlighted are '
              'true, not just against the normal/unselected fill',
        );
      },
    );
  }

  testWidgets(
    "the app's actual seeded dark palette keeps the three card states "
    'distinguishable, and keeps the combined-state hint border visible',
    (tester) async {
      // The generic Brightness.dark case above uses ThemeData(brightness:
      // dark)'s default (unseeded) scheme. This pins the same checks to the
      // exact palette lib/ui/app.dart's darkTheme actually produces --
      // Colors.indigo seeded into ColorScheme.fromSeed -- since a previous
      // review found the combined selected+highlighted border could go
      // invisible, and that regression is specific to the real palette.
      const card = CardItem(0, 9);
      final darkTheme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
      await tester.pumpWidget(MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CardTile(
                  key: const ValueKey('normal'),
                  card: card,
                  selected: false,
                  highlighted: false,
                  onTap: () {},
                ),
                CardTile(
                  key: const ValueKey('selected'),
                  card: card,
                  selected: true,
                  highlighted: false,
                  onTap: () {},
                ),
                CardTile(
                  key: const ValueKey('highlighted'),
                  card: card,
                  selected: false,
                  highlighted: true,
                  onTap: () {},
                ),
                CardTile(
                  key: const ValueKey('both'),
                  card: card,
                  selected: true,
                  highlighted: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ));

      final normal = decorationFor(tester, 'normal');
      final selected = decorationFor(tester, 'selected');
      final highlighted = decorationFor(tester, 'highlighted');
      final both = decorationFor(tester, 'both');

      expect(
        {normal.color, selected.color, highlighted.color},
        hasLength(3),
        reason: 'the real indigo dark palette must still paint normal, '
            'selected and highlighted with 3 distinct fills',
      );

      final combinedBorder = borderColorOf(both);
      expect(
        combinedBorder,
        isNot(Colors.transparent),
        reason: 'a highlighted+selected card must still show a hint border '
            'in the app\'s real dark palette',
      );
      expect(combinedBorder, isNot(both.color));
      expect(
        _contrastRatio(combinedBorder, both.color!),
        greaterThan(3.0),
        reason: 'the hint border must stay visible against the selected '
            'fill in the app\'s real dark palette, not just in a generic, '
            'unseeded dark theme',
      );
    },
  );
}
