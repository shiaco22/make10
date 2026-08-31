import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/domain/solver.dart';
import 'package:make10/game/game_session.dart';
import 'package:make10/ui/game_screen.dart';
import 'package:make10/ui/widgets/card_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

void main() {
  late StatsRepository stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stats = StatsRepository();
    await stats.load();
  });

  Future<GameSession> pumpGame(
    WidgetTester tester,
    List<int> digits,
  ) async {
    final session = await sessionWithDigits(digits, stats);
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(session: session)),
    );
    return session;
  }

  /// [pumpGame], but first sets the test surface to [size] so the real
  /// responsive layout (BoardView's LayoutBuilder, ActionBar's Wrap, etc.)
  /// runs exactly as it would on a device of that size.
  Future<GameSession> pumpGameAtSize(
    WidgetTester tester,
    List<int> digits,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return pumpGame(tester, digits);
  }

  Future<void> tapCardWithValue(WidgetTester tester, int value) async {
    final tile = find.byWidgetPredicate(
      (w) => w is CardTile && w.card.value == value,
    );
    await tester.tap(tile.first);
    await tester.pump();
  }

  /// The on-screen rect of the [CardTile] for each value in [values], in
  /// the same order. Reading the real render-box rect (rather than trusting
  /// the layout math) is what would have caught the 320pt regression: the
  /// pre-fix board wrapped the fourth card 57pt below its slot.
  List<Rect> cardRectsFor(WidgetTester tester, List<int> values) {
    return [
      for (final value in values)
        tester.getRect(find.byWidgetPredicate(
          (w) => w is CardTile && w.card.value == value,
        )),
    ];
  }

  /// The on-screen center of the [DecoratedBox] inside the [CardTile] whose
  /// card has [value].
  ///
  /// Reading a descendant like this (rather than the [CardTile] element's
  /// own render object, which is the [Transform] the shake animation
  /// applies) is what actually reflects the shake's horizontal
  /// displacement: a widget's own render object never reports its own
  /// paint transform, only what an ancestor transform does to it.
  Offset cardTileCenter(WidgetTester tester, int value) {
    final tile = find.byWidgetPredicate(
      (w) => w is CardTile && w.card.value == value,
    );
    final decoratedBox =
        find.descendant(of: tile, matching: find.byType(DecoratedBox));
    return tester.getCenter(decoratedBox);
  }

  /// Whether the [TextButton] labelled [label] (as built by ActionBar's
  /// `TextButton.icon`) currently has a live `onPressed`.
  bool actionEnabled(WidgetTester tester, String label) {
    final finder = find.widgetWithText(TextButton, label);
    expect(finder, findsOneWidget,
        reason: 'expected exactly one $label button');
    return tester.widget<TextButton>(finder).onPressed != null;
  }

  testWidgets('shows four cards at the start', (tester) async {
    await pumpGame(tester, [3, 4, 7, 9]);
    expect(find.byType(CardTile), findsNWidgets(4));
  });

  testWidgets('merging reduces the card count', (tester) async {
    await pumpGame(tester, [3, 4, 7, 9]);
    await tapCardWithValue(tester, 3);
    await tester.tap(find.text('×'));
    await tester.pump();
    await tapCardWithValue(tester, 4);
    expect(find.byType(CardTile), findsNWidgets(3));
    // A plain find.text('12') would now also match the pending-line preview
    // of the auto-selected produced card (see the next test below), so this
    // targets the card face specifically.
    expect(
      find.byWidgetPredicate((w) => w is CardTile && w.card.value == 12),
      findsOneWidget,
    );
  });

  testWidgets('a full solve shows the cleared message', (tester) async {
    final session = await pumpGame(tester, [3, 4, 7, 9]);
    while (!session.board.isFinished) {
      final move = hint(session.board.values)!;
      final left = session.board.cards[move.leftIndex];
      final right = session.board.cards[move.rightIndex];
      session.tapCard(left.id);
      session.tapOp(move.op);
      session.tapCard(right.id);
      await tester.pump();
    }
    expect(find.textContaining('クリア'), findsOneWidget);
  });

  testWidgets(
      'after a merge, the produced card is shown selected and ready for '
      'the next operator', (tester) async {
    final session = await pumpGame(tester, [3, 4, 7, 9]);
    await tapCardWithValue(tester, 3);
    await tester.tap(find.text('+'));
    await tester.pump();
    await tapCardWithValue(tester, 9);

    final producedTile = tester.widget<CardTile>(
      find.byWidgetPredicate((w) => w is CardTile && w.card.value == 12),
    );
    expect(producedTile.selected, isTrue);
    expect(session.selectedOp, isNull);
    // The pending-line preview now also shows the auto-selected card's
    // value (no operator chosen yet), on top of the card's own face.
    expect(find.text('12'), findsNWidgets(2));

    // 演算子が引き継がれていないことを機能的にも確認する:
    // すぐに次の演算子を押せて、選択中のカードに対して効く。
    await tester.tap(find.text('×'));
    await tester.pump();
    expect(session.selectedOp, Op.mul);
  });

  testWidgets('the final card is not shown selected once the board clears',
      (tester) async {
    final session = await pumpGame(tester, [3, 4, 7, 9]);
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
    final finalTile = tester.widget<CardTile>(find.byType(CardTile));
    expect(finalTile.selected, isFalse);
  });

  testWidgets('a non-exact division keeps the selection and warns',
      (tester) async {
    final session = await pumpGame(tester, [7, 2, 1, 1]);
    await tapCardWithValue(tester, 7);
    await tester.tap(find.text('÷'));
    await tester.pump();
    await tapCardWithValue(tester, 2);
    expect(find.byType(CardTile), findsNWidgets(4));
    expect(find.textContaining('割り切れません'), findsOneWidget);
    expect(session.selectedOp, isNotNull);
  });

  testWidgets(
      'a refused merge shakes the target card, and an identical repeat '
      'shakes it again', (tester) async {
    final session = await pumpGame(tester, [7, 2, 1, 1]);
    await tapCardWithValue(tester, 7);
    await tester.tap(find.text('÷'));
    await tester.pump();

    final restCenter = cardTileCenter(tester, 2);

    // 1 回目の拒否: 7 ÷ 2 は割り切れない。
    await tapCardWithValue(tester, 2);
    expect(find.textContaining('割り切れません'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      cardTileCenter(tester, 2).dx,
      isNot(closeTo(restCenter.dx, 0.01)),
      reason: 'the target card must be mid-shake shortly after the refusal',
    );

    // 震えが収まりきるまで進める -- 元の位置にきちんと戻ること。
    await tester.pump(const Duration(milliseconds: 400));
    expect(cardTileCenter(tester, 2).dx, closeTo(restCenter.dx, 0.01));

    // 2 回目、内容が前回と全く同じ拒否 -- それでも再び震えること。
    await tapCardWithValue(tester, 2);
    expect(find.textContaining('割り切れません'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      cardTileCenter(tester, 2).dx,
      isNot(closeTo(restCenter.dx, 0.01)),
      reason: 'an identical repeated refusal must shake again, not sit still '
          'just because nothing about it changed',
    );

    // 2 回の拒否を通じて、カードと演算子の選択は維持されたまま。
    expect(session.selectedCardId, isNotNull);
    expect(session.selectedOp, Op.div);

    // 震えの Ticker と短時間表示の Ticker を両方収束させてから終了する。
    await tester.pump(kRejectionMessageDuration);
  });

  testWidgets(
      'the rejection message clears itself after a short interval without '
      'another tap, keeping the selection', (tester) async {
    final session = await pumpGame(tester, [7, 2, 1, 1]);
    await tapCardWithValue(tester, 7);
    await tester.tap(find.text('÷'));
    await tester.pump();
    await tapCardWithValue(tester, 2);
    expect(find.textContaining('割り切れません'), findsOneWidget);

    // 短時間表示の途中ではまだ見えている。
    await tester.pump(
      kRejectionMessageDuration - const Duration(milliseconds: 500),
    );
    expect(find.textContaining('割り切れません'), findsOneWidget);

    // 経過後は、追加のタップなしに自動で消える。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('割り切れません'), findsNothing);
    expect(session.lastRejection, isNull);

    // 自動消去はカードと演算子の選択を壊さない（仕様 §2.5）。
    expect(session.selectedCardId, isNotNull);
    expect(session.selectedOp, Op.div);
  });

  testWidgets('hint on a dead end tells the player to step back',
      (tester) async {
    final session = await pumpGame(tester, [3, 4, 7, 9]);
    // 3*7=21 -> 4,9,21 が詰み。3*4=12 は詰みではないので使わないこと。
    final three = session.board.cards.firstWhere((c) => c.value == 3);
    final seven = session.board.cards.firstWhere((c) => c.value == 7);
    session.tapCard(three.id);
    session.tapOp(Op.mul);
    await tester.pump();
    session.tapCard(seven.id);
    await tester.pump();
    await tester.tap(find.text('ヒント'));
    await tester.pump();
    expect(find.textContaining('戻しましょう'), findsOneWidget);
  });

  testWidgets(
      'hint after a refused merge on a dead end shows the dead-end notice, '
      'not the stale rejection', (tester) async {
    await pumpGame(tester, [3, 4, 7, 9]);
    // 3*7=21 -> [4,9,21] は詰み（実測で確認済み）。3*4=12 は詰みではない
    // （12,7,9 には 5 通りの解がある）ので使わないこと。
    await tapCardWithValue(tester, 3);
    await tester.tap(find.text('×'));
    await tester.pump();
    await tapCardWithValue(tester, 7);

    // 詰みに進んだ盤面で、ヒント前に 9÷4 を拒否させ、拒否メッセージを残す。
    await tapCardWithValue(tester, 9);
    await tester.tap(find.text('÷'));
    await tester.pump();
    await tapCardWithValue(tester, 4);
    expect(find.textContaining('割り切れません'), findsOneWidget);

    await tester.tap(find.text('ヒント'));
    await tester.pump();

    expect(find.textContaining('戻しましょう'), findsOneWidget);
    expect(find.textContaining('割り切れません'), findsNothing);
  });

  testWidgets('showing the answer locks the board', (tester) async {
    await pumpGame(tester, [3, 4, 7, 9]);
    await tester.tap(find.text('答え'));
    await tester.pump();
    expect(find.text('次の問題へ'), findsOneWidget);
    await tapCardWithValue(tester, 3);
    expect(find.byType(CardTile), findsNWidgets(4));
  });

  testWidgets(
    'at 320x568 all four cards sit in one row and every one is tappable',
    (tester) async {
      final session =
          await pumpGameAtSize(tester, [3, 4, 7, 9], const Size(320, 568));

      final rects = cardRectsFor(tester, [3, 4, 7, 9]);
      expect(rects, hasLength(4));

      final tops = rects.map((r) => r.top).toList();
      for (final top in tops.skip(1)) {
        expect(
          top,
          closeTo(tops.first, 0.5),
          reason: 'all four cards must sit on the same row at 320pt width',
        );
      }

      expect(tester.takeException(), isNull);

      // The regression this guards against: at 320pt the pre-fix layout
      // wrapped to two rows, and the fourth card's on-screen position did
      // not actually hit test -- tapping its centre silently missed and
      // selectedCardId stayed null. tester.tap() taps the widget's real,
      // painted centre, exactly like the reviewer's manual probe did.
      final fourthCardId = session.board.cards[3].id;
      await tester.tap(find.byWidgetPredicate(
        (w) => w is CardTile && w.card.id == fourthCardId,
      ));
      await tester.pump();
      expect(session.selectedCardId, fourthCardId);
    },
  );

  testWidgets('at 375x667 all four cards sit in one row', (tester) async {
    await pumpGameAtSize(tester, [3, 4, 7, 9], const Size(375, 667));

    final rects = cardRectsFor(tester, [3, 4, 7, 9]);
    expect(rects, hasLength(4));
    final tops = rects.map((r) => r.top).toList();
    for (final top in tops.skip(1)) {
      expect(top, closeTo(tops.first, 0.5));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'at a tablet width the cards stay capped at their max size and centred',
    (tester) async {
      const screenWidth = 834.0;
      await pumpGameAtSize(
          tester, [3, 4, 7, 9], const Size(screenWidth, 1112));

      final rects = cardRectsFor(tester, [3, 4, 7, 9]);
      expect(rects, hasLength(4));

      for (final r in rects) {
        expect(
          r.width,
          closeTo(88, 0.5),
          reason: 'cards must reach, but not exceed, their 88-wide maximum '
              'on a tablet-sized screen',
        );
        expect(r.height, closeTo(112, 0.5));
      }

      final rowLeft =
          rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
      final rowRight =
          rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
      final rowCenter = (rowLeft + rowRight) / 2;
      expect(
        rowCenter,
        closeTo(screenWidth / 2, 1.0),
        reason: 'the row of cards must stay horizontally centred',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'after a clear, only next-puzzle is offered -- undo/reset/skip disabled',
    (tester) async {
      final session = await pumpGame(tester, [3, 4, 7, 9]);
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

      expect(actionEnabled(tester, '戻す'), isFalse);
      expect(actionEnabled(tester, '最初から'), isFalse);
      expect(actionEnabled(tester, 'スキップ'), isFalse);
      expect(find.text('次の問題へ'), findsOneWidget);
    },
  );

  testWidgets(
    'after answer shown, only next-puzzle is offered -- undo/reset/skip '
    'disabled',
    (tester) async {
      await pumpGame(tester, [3, 4, 7, 9]);
      await tester.tap(find.text('答え'));
      await tester.pump();

      expect(actionEnabled(tester, '戻す'), isFalse);
      expect(actionEnabled(tester, '最初から'), isFalse);
      expect(actionEnabled(tester, 'スキップ'), isFalse);
      expect(find.text('次の問題へ'), findsOneWidget);
    },
  );

  testWidgets(
    'time spent backgrounded is excluded from the recorded solve time',
    (tester) async {
      final session = await pumpGame(tester, [3, 4, 7, 9]);

      // バックグラウンドへ。実時間の lifecycle 遷移を本物どおりに
      // WidgetsBinding 経由で流し込む（GameScreen が
      // WidgetsBindingObserver として拾う想定）。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      // GameSession の Stopwatch は意図的に実時間で動く（仕様上、別の
      // 計測方式には切り替えない）。一方 testWidgets は FakeAsync 上で
      // 動くため、素の Future.delayed はフェイクの時計を誰も進めない限り
      // 永遠に発火しない。runAsync で本物の非同期の外へ出て、実際に
      // 壁時計の時間を経過させる。
      const backgroundGap = Duration(milliseconds: 800);
      await tester.runAsync(() => Future<void>.delayed(backgroundGap));

      // フォアグラウンドへ復帰し、直後にクリアする
      // （復帰後の実プレイ時間はミリ秒オーダーに収まるはず）。
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
      // recordSolved は tapCard の中で（await せず）呼ばれるが、
      // _practice の更新自体は最初の await より前、つまり同期的に効く。
      // pump() でひと呼吸置いて確実にする。
      await tester.pump();

      // バックグラウンドの 800ms がそのまま数えられていれば totalTimeMs
      // は 800 以上になる。実際に「プレイ」した時間だけが数えられていれば、
      // それよりずっと小さいはず。
      expect(
        stats.practice(Difficulty.normal).totalTimeMs,
        lessThan(backgroundGap.inMilliseconds ~/ 2),
      );
    },
  );
}
