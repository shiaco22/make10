import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
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

  Future<void> tapCardWithValue(WidgetTester tester, int value) async {
    final tile = find.byWidgetPredicate(
      (w) => w is CardTile && w.card.value == value,
    );
    await tester.tap(tile.first);
    await tester.pump();
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
    expect(find.text('12'), findsOneWidget);
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

  testWidgets('showing the answer locks the board', (tester) async {
    await pumpGame(tester, [3, 4, 7, 9]);
    await tester.tap(find.text('答え'));
    await tester.pump();
    expect(find.text('次の問題へ'), findsOneWidget);
    await tapCardWithValue(tester, 3);
    expect(find.byType(CardTile), findsNWidgets(4));
  });
}
