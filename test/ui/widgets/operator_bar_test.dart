import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/ui/widgets/operator_bar.dart';

void main() {
  // GameScreen wraps its body in Padding(EdgeInsets.all(16)) before it ever
  // lays out OperatorBar, so the bar only ever sees (screen width - 32).
  // Reproduce that padding here instead of pumping OperatorBar bare.
  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OperatorBar(selected: null, onTap: (_) {}),
          ),
        ),
      ),
    );
  }

  /// Pumps a bare [OperatorBar] with the given pending/hinted operators.
  Future<void> pumpBar(
    WidgetTester tester, {
    Op? selected,
    Op? hintedOp,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OperatorBar(
              selected: selected,
              hintedOp: hintedOp,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  /// The actually-painted background [Material] color of the button for
  /// [op] (located by its symbol text, e.g. '+'). Reading the rendered
  /// [Material] (as the rest of this codebase's widget tests do for their
  /// own "what actually painted" checks) sidesteps depending on exactly
  /// how [FilledButton.styleFrom] represents its resolved style.
  Color markedColorOf(WidgetTester tester, Op op) {
    final buttonFinder = find.widgetWithText(FilledButton, opSymbol(op));
    final materialFinder = find
        .descendant(of: buttonFinder, matching: find.byType(Material))
        .first;
    return tester.widget<Material>(materialFinder).color!;
  }

  testWidgets(
    'a hinted operator with nothing pending gets the same mark as a '
    'pending selection',
    (tester) async {
      await pumpBar(tester, selected: Op.add);
      final pendingColor = markedColorOf(tester, Op.add);

      await pumpBar(tester, hintedOp: Op.add);
      final hintedColor = markedColorOf(tester, Op.add);

      expect(
        hintedColor,
        pendingColor,
        reason: 'the hinted mark must reuse the exact same visual as a '
            'pending operator selection',
      );
    },
  );

  testWidgets(
    'with nothing pending and no hint, no operator is marked',
    (tester) async {
      await pumpBar(tester);
      final scheme =
          Theme.of(tester.element(find.byType(OperatorBar))).colorScheme;
      for (final op in Op.values) {
        expect(markedColorOf(tester, op), scheme.secondaryContainer);
      }
    },
  );

  testWidgets(
    'a hinted operator is marked when no operator is pending',
    (tester) async {
      await pumpBar(tester, hintedOp: Op.div);
      final scheme =
          Theme.of(tester.element(find.byType(OperatorBar))).colorScheme;

      expect(markedColorOf(tester, Op.div), scheme.primary);
      for (final other in Op.values.where((o) => o != Op.div)) {
        expect(markedColorOf(tester, other), scheme.secondaryContainer);
      }
    },
  );

  testWidgets(
    'a pending selection wins the mark over a different hinted operator',
    (tester) async {
      await pumpBar(tester, selected: Op.add, hintedOp: Op.mul);
      final scheme =
          Theme.of(tester.element(find.byType(OperatorBar))).colorScheme;

      expect(
        markedColorOf(tester, Op.add),
        scheme.primary,
        reason: 'the pending operator must still be marked',
      );
      expect(
        markedColorOf(tester, Op.mul),
        scheme.secondaryContainer,
        reason: 'a different hinted operator must not also be marked '
            'while an operator is genuinely pending',
      );
    },
  );

  testWidgets(
    'does not overflow on a 320pt-wide screen (iPhone-SE class)',
    (tester) async {
      await pumpAtWidth(tester, 320);
      // 4 buttons x (64 width + 6+6 padding) = 304, but 320-32(padding)
      // leaves only 288 -- a plain Row overflows by 16px here.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'buttons stay at full size on a 375pt-wide screen',
    (tester) async {
      await pumpAtWidth(tester, 375);
      expect(tester.takeException(), isNull);

      // At 375 wide there is 39px of slack (375-32-4*76=39), so the fix
      // must leave this untouched: each operator button should still
      // render at its natural 64x64 size, not scaled down.
      final buttonSize = tester.getSize(
        find
            .descendant(
              of: find.byType(OperatorBar),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(buttonSize, const Size(64, 64));
    },
  );
}
