// Widget tests for the tablet-scaling behaviour: BoardView/CardTile,
// OperatorBar, ActionBar, HomeScreen and DifficultyScreen all grow on a
// tablet-sized viewport (MediaQuery shortest side >= 600, see
// lib/ui/widgets/responsive.dart), while staying pixel-for-pixel unchanged
// on a phone-sized one.
//
// Target viewports under test (logical/CSS pixels -- what Safari reports
// and what Flutter web uses 1:1):
//   iPad / iPad Air   820 x 1180 (portrait) / 1180 x 820 (landscape)
//   iPad Pro 12.9"    1024 x 1366 (portrait) / 1366 x 1024 (landscape)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/solver.dart';
import 'package:make10/game/game_session.dart';
import 'package:make10/ui/app.dart';
import 'package:make10/ui/difficulty_screen.dart';
import 'package:make10/ui/game_screen.dart';
import 'package:make10/ui/widgets/action_bar.dart';
import 'package:make10/ui/widgets/board_view.dart';
import 'package:make10/ui/widgets/card_tile.dart';
import 'package:make10/ui/widgets/operator_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

void main() {
  late StatsRepository stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stats = StatsRepository();
    await stats.load();
    // rootBundle caches loadString's Future per key across the whole
    // process; a fresh evict per test lets each test's own load of
    // assets/puzzles.json actually run instead of hanging on another
    // test's cached (and already-consumed) Future. See app_boot_test.dart.
    rootBundle.evict('assets/puzzles.json');
  });

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<GameSession> pumpGameAtSize(WidgetTester tester, Size size) async {
    await setSize(tester, size);
    final session = await sessionWithDigits([3, 4, 7, 9], stats);
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: session)));
    // CardTile sizes itself with an AnimatedContainer. Most tests here
    // only ever pump one size and this settle is a no-op (a widget's very
    // first build never animates from some other value). But a few tests
    // re-pump the *same* GameScreen tree at a second size within one test
    // to compare geometry -- since the four CardTiles keep their element
    // identity across that rebuild (ValueKey(card.id) matches when both
    // sessions deal the same digits), a bare pumpWidget would only
    // capture the transition's first frame, still showing the old size.
    // Settling past AnimatedContainer's 120ms clears that regardless of
    // which case this is.
    await tester.pump(const Duration(milliseconds: 200));
    return session;
  }

  List<Rect> cardRects(WidgetTester tester) {
    return [
      for (final v in [3, 4, 7, 9])
        tester.getRect(find.byWidgetPredicate(
          (w) => w is CardTile && w.card.value == v,
        )),
    ];
  }

  Future<void> pumpHomeAtSize(WidgetTester tester, Size size) async {
    await setSize(tester, size);
    await tester.pumpWidget(const ProviderScope(child: Make10App()));
    for (var i = 0; i < 40; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpDifficultyAtSize(WidgetTester tester, Size size) async {
    await setSize(tester, size);
    await tester.pumpWidget(MaterialApp(
      home: DifficultyScreen(title: 'テスト', onSelected: (_) {}),
    ));
  }

  /// Mirrors how GameScreen actually presents OperatorBar/ActionBar: both
  /// sit inside the body's `Padding(EdgeInsets.all(16))`, which is exactly
  /// how much width they really get to work with.
  Future<void> pumpOperatorBarAtSize(WidgetTester tester, Size size) async {
    await setSize(tester, size);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: OperatorBar(selected: null, onTap: (_) {}),
        ),
      ),
    ));
  }

  Future<void> pumpActionBarAtSize(WidgetTester tester, Size size) async {
    await setSize(tester, size);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ActionBar(
            canUndo: true,
            interactionEnabled: true,
            assistEnabled: true,
            onUndo: () {},
            onReset: () {},
            onHint: () {},
            onAnswer: () {},
            onSkip: () {},
          ),
        ),
      ),
    ));
  }

  Size operatorButtonSize(WidgetTester tester) =>
      tester.getSize(find.widgetWithText(FilledButton, '+'));

  Size homeButtonSize(WidgetTester tester) =>
      tester.getSize(find.widgetWithText(FilledButton, 'プラクティス'));

  Size difficultyButtonSize(WidgetTester tester) =>
      tester.getSize(find.widgetWithText(FilledButton, Difficulty.easy.label));

  /// Asserts [tablet] is measurably bigger than [phone] in both dimensions
  /// and clears Apple's 44x44 minimum touch target.
  void expectGrows(Size phone, Size tablet, String label) {
    expect(
      tablet.width,
      greaterThan(phone.width * 1.05),
      reason: '$label width must be measurably larger on a tablet',
    );
    expect(
      tablet.height,
      greaterThan(phone.height * 1.05),
      reason: '$label height must be measurably larger on a tablet',
    );
    expect(
      tablet.width,
      greaterThanOrEqualTo(44),
      reason: '$label width must clear the 44x44 minimum touch target',
    );
    expect(
      tablet.height,
      greaterThanOrEqualTo(44),
      reason: '$label height must clear the 44x44 minimum touch target',
    );
  }

  const phoneSize = Size(375, 812);
  const tabletSizes = [Size(820, 1180), Size(1180, 820)];
  const landscapeSizes = [Size(1180, 820), Size(1366, 1024)];

  group(
      'criterion 1: cards are meaningfully larger on a tablet, still one '
      'row, still grouped and centred', () {
    for (final size in tabletSizes) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await pumpGameAtSize(tester, phoneSize);
        final phoneCard = cardRects(tester).first.size;

        await pumpGameAtSize(tester, size);
        final rects = cardRects(tester);
        expect(rects, hasLength(4));
        final tabletCard = rects.first.size;

        for (final r in rects) {
          expect(r.width, closeTo(tabletCard.width, 0.5));
          expect(r.height, closeTo(tabletCard.height, 0.5));
        }

        final multiple = tabletCard.width / phoneCard.width;
        // Printed unconditionally so the achieved multiple always shows
        // up in `flutter test` output, not just on failure.
        // ignore: avoid_print
        print(
          'card size at ${size.width.toInt()}x${size.height.toInt()}: '
          '${tabletCard.width.toStringAsFixed(1)}x'
          '${tabletCard.height.toStringAsFixed(1)} vs phone (375x812) '
          '${phoneCard.width.toStringAsFixed(1)}x'
          '${phoneCard.height.toStringAsFixed(1)} '
          '-> x${multiple.toStringAsFixed(2)}',
        );
        expect(
          tabletCard.width,
          greaterThan(phoneCard.width * 1.3),
          reason: 'cards must be meaningfully larger on a tablet than on a '
              'phone (measured x${multiple.toStringAsFixed(2)})',
        );

        final tops = rects.map((r) => r.top).toList();
        for (final top in tops.skip(1)) {
          expect(top, closeTo(tops.first, 0.5),
              reason: 'all four cards must still sit on a single row');
        }

        final rowLeft =
            rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final rowRight =
            rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        final rowCenter = (rowLeft + rowRight) / 2;
        expect(
          rowCenter,
          closeTo(size.width / 2, 1.0),
          reason: 'the board must stay horizontally centred',
        );
        expect(
          rowRight - rowLeft,
          lessThan(size.width * 0.8),
          reason: 'the four cards must read as one grouped cluster, not '
              'spread edge to edge across the tablet screen',
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group(
      'criterion 2: home/difficulty/operator buttons grow on a tablet and '
      'clear the 44x44 minimum', () {
    for (final size in tabletSizes) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await pumpHomeAtSize(tester, phoneSize);
        final phoneHome = homeButtonSize(tester);
        await pumpDifficultyAtSize(tester, phoneSize);
        final phoneDiff = difficultyButtonSize(tester);
        await pumpOperatorBarAtSize(tester, phoneSize);
        final phoneOp = operatorButtonSize(tester);

        await pumpHomeAtSize(tester, size);
        final tabletHome = homeButtonSize(tester);
        await pumpDifficultyAtSize(tester, size);
        final tabletDiff = difficultyButtonSize(tester);
        await pumpOperatorBarAtSize(tester, size);
        final tabletOp = operatorButtonSize(tester);

        // ignore: avoid_print
        print('home button ${size.width.toInt()}x${size.height.toInt()}: '
            '$tabletHome vs phone $phoneHome');
        // ignore: avoid_print
        print('difficulty button '
            '${size.width.toInt()}x${size.height.toInt()}: $tabletDiff vs '
            'phone $phoneDiff');
        // ignore: avoid_print
        print('operator button ${size.width.toInt()}x${size.height.toInt()}'
            ': $tabletOp vs phone $phoneOp');

        expectGrows(phoneHome, tabletHome, 'home button');
        expectGrows(phoneDiff, tabletDiff, 'difficulty button');
        expectGrows(phoneOp, tabletOp, 'operator button');
      });
    }
  });

  group(
      'criterion 3: landscape tablet sizes do not overflow; the operator '
      'and action bars stay fully on screen', () {
    for (final size in landscapeSizes) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}, idle '
          'playing state', (tester) async {
        await pumpGameAtSize(tester, size);
        expect(tester.takeException(), isNull);

        final operatorRect = tester.getRect(find.byType(OperatorBar));
        final actionRect = tester.getRect(find.byType(ActionBar));

        for (final r in [operatorRect, actionRect]) {
          expect(r.left, greaterThanOrEqualTo(-0.5));
          expect(r.top, greaterThanOrEqualTo(-0.5));
          expect(r.right, lessThanOrEqualTo(size.width + 0.5));
          expect(r.bottom, lessThanOrEqualTo(size.height + 0.5));
        }
      });

      testWidgets(
          'at ${size.width.toInt()}x${size.height.toInt()}, cleared state '
          '(tallest optional content above the bars)', (tester) async {
        final session = await pumpGameAtSize(tester, size);
        // Drive to the "cleared" phase, which adds the tallest of the
        // optional notice states (a headline plus a button) above the
        // operator/action bars -- the actual worst case for vertical
        // space, not just the idle state.
        while (!session.board.isFinished) {
          final move = hint(session.board.values)!;
          final left = session.board.cards[move.leftIndex];
          final right = session.board.cards[move.rightIndex];
          session.tapCard(left.id);
          session.tapOp(move.op);
          session.tapCard(right.id);
          await tester.pump();
        }
        expect(session.phase, PhaseKind.cleared);
        expect(tester.takeException(), isNull);

        final operatorRect = tester.getRect(find.byType(OperatorBar));
        final actionRect = tester.getRect(find.byType(ActionBar));
        for (final r in [operatorRect, actionRect]) {
          expect(r.top, greaterThanOrEqualTo(-0.5));
          expect(r.bottom, lessThanOrEqualTo(size.height + 0.5));
        }
      });
    }
  });

  group('criterion 4: the action bar fits on a single row on a tablet', () {
    for (final size in tabletSizes) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}, '
          'standalone', (tester) async {
        await pumpActionBarAtSize(tester, size);
        expect(tester.takeException(), isNull);

        final buttons = find.descendant(
          of: find.byType(ActionBar),
          matching: find.byType(TextButton),
        );
        expect(buttons, findsNWidgets(5));
        final tops = [
          for (var i = 0; i < 5; i++) tester.getRect(buttons.at(i)).top,
        ];
        for (final top in tops.skip(1)) {
          expect(top, closeTo(tops.first, 0.5),
              reason: 'the action bar must fit on a single row on a '
                  'tablet-sized screen');
        }
      });

      testWidgets(
          'at ${size.width.toInt()}x${size.height.toInt()}, inside the '
          'real GameScreen', (tester) async {
        await pumpGameAtSize(tester, size);
        expect(tester.takeException(), isNull);

        final buttons = find.descendant(
          of: find.byType(ActionBar),
          matching: find.byType(TextButton),
        );
        expect(buttons, findsNWidgets(5));
        final tops = [
          for (var i = 0; i < 5; i++) tester.getRect(buttons.at(i)).top,
        ];
        for (final top in tops.skip(1)) {
          expect(top, closeTo(tops.first, 0.5));
        }
      });
    }
  });

  group('criterion 5 (regression): 375x812 phone sizes are unchanged', () {
    // Captured by running this exact scenario against the pre-scaling
    // implementation (see the tablet layout task report for the full
    // before/after table). Pinning these as literal numbers -- not
    // deriving them from uiScale -- is the point: uiScale returning 1.0
    // below the tablet breakpoint is exactly the thing this test must
    // catch if it ever regresses.
    const expectedCardWidth = 76.75;
    const expectedCardHeight = 97.68181818181819;
    const expectedBoardWidth = 343.0;
    const expectedOperator = Size(64, 64);
    const expectedHome = Size(240, 56);
    const expectedDifficulty = Size(220, 56);

    testWidgets('card size and board width', (tester) async {
      await pumpGameAtSize(tester, phoneSize);
      final rects = cardRects(tester);
      expect(rects.first.width, closeTo(expectedCardWidth, 0.1));
      expect(rects.first.height, closeTo(expectedCardHeight, 0.1));
      final left = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
      final right =
          rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
      expect(right - left, closeTo(expectedBoardWidth, 0.1));
    });

    testWidgets('operator button size', (tester) async {
      await pumpOperatorBarAtSize(tester, phoneSize);
      final size = operatorButtonSize(tester);
      expect(size.width, closeTo(expectedOperator.width, 0.1));
      expect(size.height, closeTo(expectedOperator.height, 0.1));
    });

    testWidgets('home button size', (tester) async {
      await pumpHomeAtSize(tester, phoneSize);
      final size = homeButtonSize(tester);
      expect(size.width, closeTo(expectedHome.width, 0.1));
      expect(size.height, closeTo(expectedHome.height, 0.1));
    });

    testWidgets('difficulty button size', (tester) async {
      await pumpDifficultyAtSize(tester, phoneSize);
      final size = difficultyButtonSize(tester);
      expect(size.width, closeTo(expectedDifficulty.width, 0.1));
      expect(size.height, closeTo(expectedDifficulty.height, 0.1));
    });
  });

  // Criterion 6 (regression: 320x568 no overflow, fourth card tappable) is
  // already covered by "at 320x568 all four cards sit in one row and
  // every one is tappable" in test/ui/game_screen_test.dart. Since scale
  // is 1.0 below the 600 tablet breakpoint, none of this feature's changes
  // touch that code path; the existing test is left as-is and re-verified
  // (see the task report) rather than duplicated here.

  // --- New requirements added for the "tablet compose" fix below -----------
  //
  // The four groups below are new for this task (composition + retuned
  // scale). Each was run against the pre-fix code first; see the task
  // report for what was actually observed for each ("must fail against the
  // current code... say honestly if any passes either way").

  group(
      'new requirement 1: the board and the operator bar stay close '
      'together on a tall portrait tablet', () {
    testWidgets('at 820x1180, the card-row-to-operator-bar gap is small',
        (tester) async {
      await pumpGameAtSize(tester, const Size(820, 1180));
      expect(tester.takeException(), isNull);

      final cardsBottom = cardRects(tester)
          .map((r) => r.bottom)
          .reduce((a, b) => a > b ? a : b);
      final operatorTop = tester.getRect(find.byType(OperatorBar)).top;
      final gap = operatorTop - cardsBottom;

      // ignore: avoid_print
      print('card-row-to-operator-bar gap at 820x1180: '
          '${gap.toStringAsFixed(1)}px');

      // Measured ~350px against the pre-fix implementation, where the
      // board's Expanded absorbs 100% of a tall screen's slack, floating
      // the board in the middle of the screen while the operator bar
      // stays pinned near the bottom. 120px is chosen as comfortably
      // "thumb-reachable, still one visual group" -- it covers the
      // notice line's reserved height (24px) plus the explicit 12px
      // SizedBox gap plus real breathing room, while remaining a small
      // fraction of the ~350px this must actually fail against.
      expect(
        gap,
        lessThanOrEqualTo(120),
        reason: 'the board and the operator bar must stay close together '
            'on a tall tablet screen, not be pulled to opposite ends '
            '(measured ${gap.toStringAsFixed(1)}px)',
      );
    });
  });

  group(
      'new requirement 2: the home screen buttons occupy a sensibly '
      'larger share of the screen width than today', () {
    // Measured today (pre-fix uiScale): the button is 314.7pt wide
    // regardless of orientation (uiScale depends only on the shared
    // 820pt shortest side), i.e. ~38.4% of an 820-wide portrait screen
    // and ~26.7% of a 1180-wide landscape screen. The thresholds below
    // sit clearly above both of those measurements without asking for a
    // near-full-bleed button.
    // Not `const`: Size's `==` is a normal (non-primitive) override, which
    // Dart allows for a runtime Map literal's keys but not a const one.
    final minShare = {
      const Size(820, 1180): 0.45,
      const Size(1180, 820): 0.30,
    };

    for (final size in tabletSizes) {
      testWidgets('at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await pumpHomeAtSize(tester, size);
        final button = homeButtonSize(tester);
        final share = button.width / size.width;

        // ignore: avoid_print
        print('home button share at ${size.width.toInt()}x'
            '${size.height.toInt()}: ${(share * 100).toStringAsFixed(1)}% '
            '(${button.width.toStringAsFixed(1)}pt of '
            '${size.width.toInt()}pt)');

        expect(
          share,
          greaterThanOrEqualTo(minShare[size]!),
          reason: 'the primary button must occupy a sensibly larger '
              'share of the width than the ~38%/~27% measured today '
              '(measured ${(share * 100).toStringAsFixed(1)}%)',
        );
      });
    }
  });

  group(
      'new requirement 3: iPad mini landscape (the shortest tablet) '
      'fits everything on screen', () {
    const size = Size(1133, 744);

    testWidgets('idle playing state', (tester) async {
      await pumpGameAtSize(tester, size);
      expect(tester.takeException(), isNull);

      final boardRect = tester.getRect(find.byType(BoardView));
      final operatorRect = tester.getRect(find.byType(OperatorBar));
      final actionRect = tester.getRect(find.byType(ActionBar));

      for (final r in [boardRect, operatorRect, actionRect]) {
        expect(r.left, greaterThanOrEqualTo(-0.5));
        expect(r.top, greaterThanOrEqualTo(-0.5));
        expect(r.right, lessThanOrEqualTo(size.width + 0.5));
        expect(r.bottom, lessThanOrEqualTo(size.height + 0.5));
      }
    });

    testWidgets('cleared state (tallest optional content above the bars)',
        (tester) async {
      final session = await pumpGameAtSize(tester, size);
      while (!session.board.isFinished) {
        final move = hint(session.board.values)!;
        final left = session.board.cards[move.leftIndex];
        final right = session.board.cards[move.rightIndex];
        session.tapCard(left.id);
        session.tapOp(move.op);
        session.tapCard(right.id);
        await tester.pump();
      }
      expect(session.phase, PhaseKind.cleared);
      expect(tester.takeException(), isNull);

      final boardRect = tester.getRect(find.byType(BoardView));
      final operatorRect = tester.getRect(find.byType(OperatorBar));
      final actionRect = tester.getRect(find.byType(ActionBar));
      for (final r in [boardRect, operatorRect, actionRect]) {
        expect(r.top, greaterThanOrEqualTo(-0.5));
        expect(r.bottom, lessThanOrEqualTo(size.height + 0.5));
      }
    });
  });

  group(
      'new requirement 4: iPad Pro landscape does not overflow and does '
      'not stretch the content edge to edge', () {
    const size = Size(1366, 1024);

    testWidgets('idle playing state', (tester) async {
      await pumpGameAtSize(tester, size);
      expect(tester.takeException(), isNull);

      final boardRect = tester.getRect(find.byType(BoardView));
      final operatorRect = tester.getRect(find.byType(OperatorBar));
      final actionRect = tester.getRect(find.byType(ActionBar));

      for (final r in [boardRect, operatorRect, actionRect]) {
        expect(r.top, greaterThanOrEqualTo(-0.5));
        expect(r.bottom, lessThanOrEqualTo(size.height + 0.5));
      }

      // BoardView's own layout box (found via find.byType) always fills
      // its slot's full width -- it is a Center, which (per
      // RenderPositionedBox) claims the incoming constraint's maxWidth
      // whenever that width is bounded, regardless of how narrow its
      // child actually paints. So "edge to edge" for the board is judged
      // by the actual painted card row instead (as criterion 1 above
      // does), not BoardView's own hit-testable bounds. OperatorBar and
      // ActionBar do not have this gap: both are rooted in a FittedBox,
      // which sizes itself to its child's natural size when the incoming
      // constraint is merely loose (only an *unbounded* constraint makes
      // it fill available space), so their own rects already reflect
      // what is actually painted.
      final cardRow = cardRects(tester);
      final rowLeft = cardRow.map((r) => r.left).reduce((a, b) => a < b ? a : b);
      final rowRight = cardRow.map((r) => r.right).reduce((a, b) => a > b ? a : b);

      for (final entry in {
        'board': rowRight - rowLeft,
        'operator bar': operatorRect.width,
        'action bar': actionRect.width,
      }.entries) {
        expect(
          entry.value,
          lessThan(size.width * 0.8),
          reason: '${entry.key} must read as a centred group with '
              'visible margin on a very wide screen, not span edge to '
              'edge',
        );
      }
    });
  });
}
