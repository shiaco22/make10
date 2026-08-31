import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/board.dart';
import 'package:make10/ui/app.dart';
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
        expect(normal.color, scheme.outline);
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

  for (final entry in <String, ThemeData>{
    'light': Make10App.lightTheme,
    'dark': Make10App.darkTheme,
  }.entries) {
    testWidgets(
      "the app's real ${entry.key} theme paints the normal card "
      'distinguishably from the page behind it',
      (tester) async {
        // Regression test: the normal (unselected) fill used to be painted
        // with `theme.cardColor`, which Material 3 defaults to
        // `colorScheme.surface` -- the exact color Scaffold paints behind
        // it (see ThemeData's `cardColor ??= colorScheme.surface` and
        // `scaffoldBackgroundColor ??= colorScheme.surface`). The number
        // text stayed legible (it contrasts with the card), but the card
        // itself was invisible against the page: only the selected and
        // highlighted states looked like cards at all.
        await tester.pumpWidget(MaterialApp(
          theme: entry.value,
          home: Scaffold(
            body: Center(
              child: CardTile(
                key: const ValueKey('normal'),
                card: const CardItem(0, 9),
                selected: false,
                highlighted: false,
                onTap: () {},
              ),
            ),
          ),
        ));

        final cardFill = decorationFor(tester, 'normal').color!;

        // The actually-painted background of the page the card sits on:
        // Scaffold paints it via its own Material(color: ...), so read
        // that widget rather than re-deriving the color from the theme.
        final scaffoldMaterial = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(Scaffold),
                matching: find.byType(Material),
              )
              .first,
        );
        final pageColor = scaffoldMaterial.color!;

        final ratio = _contrastRatio(cardFill, pageColor);
        // Printed unconditionally (not just on failure) so the measured
        // ratio always shows up in `flutter test` output.
        // ignore: avoid_print
        print(
          'normal card vs page background contrast (${entry.key}): '
          'card=$cardFill page=$pageColor ratio=${ratio.toStringAsFixed(3)}',
        );

        expect(
          cardFill,
          isNot(pageColor),
          reason: 'the normal card must not be painted the exact same '
              'color as the page behind it (${entry.key} theme)',
        );
        // WCAG 2.1 SC 1.4.11 (Non-text Contrast) sets 3:1 as the minimum
        // ratio for a UI component's boundary against its adjacent
        // color(s) -- the same bar already used above for the hint
        // border. The card's edge against the page is exactly that kind
        // of boundary, so the same threshold applies here.
        expect(
          ratio,
          greaterThan(3.0),
          reason: 'the normal (unselected) card must be visibly distinct '
              'from the page it sits on, not just from the text drawn on '
              'top of it (${entry.key} theme)',
        );
      },
    );
  }
}
