import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
