import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/board.dart';
import 'package:make10/ui/widgets/board_view.dart';
import 'package:make10/ui/widgets/card_tile.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  /// The actually-painted decoration for the [CardTile] whose card has
  /// [cardId]. Reading this (rather than `AnimatedContainer.decoration`,
  /// which always reports the declarative target regardless of animation
  /// progress) is what catches a decoration that is still mid-animation.
  BoxDecoration decorationOfCard(WidgetTester tester, int cardId) {
    final cardTileFinder = find.byWidgetPredicate(
      (widget) => widget is CardTile && widget.card.id == cardId,
    );
    expect(
      cardTileFinder,
      findsOneWidget,
      reason: 'expected exactly one CardTile for card id $cardId',
    );
    final decoratedBoxFinder = find.descendant(
      of: cardTileFinder,
      matching: find.byType(DecoratedBox),
    );
    expect(decoratedBoxFinder, findsOneWidget);
    final box = tester.widget<DecoratedBox>(decoratedBoxFinder);
    return box.decoration as BoxDecoration;
  }

  testWidgets(
    'a highlighted survivor keeps its highlight color immediately after a '
    'merge shifts it into an earlier slot a plain card used to hold',
    (tester) async {
      // Before the merge: three cards. Only card 2 (the last one) is
      // highlighted; cards 0 and 1 are plain.
      const before = <CardItem>[
        CardItem(0, 3),
        CardItem(1, 4),
        CardItem(2, 7),
      ];
      await tester.pumpWidget(wrap(BoardView(
        cards: before,
        selectedId: null,
        highlightedIds: const {2},
        onTapCard: (_) {},
      )));

      final scheme =
          Theme.of(tester.element(find.byType(BoardView))).colorScheme;

      // Sanity check: the highlight paints correctly before the merge.
      final beforeDecoration = decorationOfCard(tester, 2);
      expect(beforeDecoration.color, scheme.tertiaryContainer);
      expect(
        (beforeDecoration.border as Border).top.color,
        scheme.tertiary,
      );

      // The merge: cards 0 and 1 are consumed by an operation; card 2
      // survives, still highlighted, and now sits at index 0 -- a slot
      // that a plain (unhighlighted) card used to hold. A newly produced
      // card (id 4) is appended after it.
      const after = <CardItem>[
        CardItem(2, 7),
        CardItem(4, 11),
      ];
      await tester.pumpWidget(wrap(BoardView(
        cards: after,
        selectedId: null,
        highlightedIds: const {2},
        onTapCard: (_) {},
      )));
      // Check an intermediate frame partway through AnimatedContainer's
      // 120ms transition: long enough that an animation left running would
      // clearly show a blended, in-between color; short enough that it
      // would not yet have reached the (correct-looking) end value. Reading
      // the painted DecoratedBox here is what catches the bug -- asserting
      // on AnimatedContainer.decoration would read the declarative target
      // and pass either way.
      await tester.pump(const Duration(milliseconds: 40));

      final afterDecoration = decorationOfCard(tester, 2);
      expect(
        afterDecoration.color,
        scheme.tertiaryContainer,
        reason: 'card 2 was highlighted both before and after the merge; '
            'it must keep painting its highlight color immediately, not '
            'fade in from the normal color the previous occupant of this '
            'slot had',
      );
      expect(
        (afterDecoration.border as Border).top.color,
        scheme.tertiary,
        reason: 'the highlight border must also stay immediate, not fade '
            'in from transparent',
      );
    },
  );
}
