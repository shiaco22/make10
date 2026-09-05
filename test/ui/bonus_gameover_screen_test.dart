import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/game/bonus_session.dart';
import 'package:make10/ui/bonus_game_screen.dart';
import 'package:make10/ui/bonus_result_screen.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

Future<BonusSession> sessionWith(
  BonusGrid grid, {
  int score = 0,
  int repairsUsed = 0,
  int seed = 0,
}) async {
  final repo = BonusRepository();
  await repo.load();
  return BonusSession(
    repository: repo,
    grid: grid,
    score: score,
    repairsUsed: repairsUsed,
    random: Random(seed),
  );
}

Future<void> pumpGame(WidgetTester tester, BonusSession session) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(home: BonusGameScreen(session: session, onExit: () {})),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('残り回数の表示', () {
    testWidgets('最初は上限いっぱいを出す', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      expect(find.text('入れ替え $kBonusRepairLimit'), findsOneWidget);
    });

    testWidgets('使った分だけ減って見える', (tester) async {
      await pumpGame(
        tester,
        await sessionWith(fiveTwosGrid(), repairsUsed: 4),
      );
      expect(find.text('入れ替え ${kBonusRepairLimit - 4}'), findsOneWidget);
    });

    testWidgets('残り 0 では次で終わることを伝える', (tester) async {
      await pumpGame(
        tester,
        await sessionWith(fiveTwosGrid(), repairsUsed: kBonusRepairLimit),
      );
      expect(find.text('入れ替え 0'), findsOneWidget);
      expect(find.textContaining('次に詰んだら終わり'), findsOneWidget);
    });
  });

  group('ゲームオーバーの重ね表示', () {
    /// 入れ替えを使い切った状態から打ち続け、ゲームオーバーにする。
    ///
    /// 詰みは 8 タップに 1 回起きるので、残り 0 から打てばすぐ終わる。
    /// 終わらなければテスト側の前提が壊れているので、はっきり失敗させる。
    Future<BonusSession> playToGameOver({int seed = 0}) async {
      for (var s = seed; s < seed + 30; s++) {
        final session = await sessionWith(
          BonusGrid.deal(Random(s)),
          repairsUsed: kBonusRepairLimit,
          seed: s,
        );
        for (var move = 0; move < 200 && !session.isOver; move++) {
          final tappable = [
            for (var i = 0; i < kBonusCells; i++)
              if (session.grid.canTap(i)) i,
          ];
          if (tappable.isEmpty) break;
          session.tap(tappable.first);
        }
        if (session.isGameOver) return session;
        session.dispose();
      }
      fail('入れ替えの残り 0 から 30 シード試してもゲームオーバーにならなかった');
    }

    testWidgets('盤面を出したまま重ねる', (tester) async {
      final session = await playToGameOver();
      await pumpGame(tester, session);
      expect(find.text('ゲームオーバー'), findsOneWidget);
      expect(find.text('打つ手がありません'), findsOneWidget);
      // 自分を詰ませた盤面が見えていることが、この表示の目的そのもの。
      expect(find.byType(BonusGridView), findsOneWidget);
      // まだ結果画面ではない。
      expect(find.byType(BonusResultScreen), findsNothing);
    });

    testWidgets('重ね表示の間はやめるボタンが操作できない', (tester) async {
      // 終わったゲームに対して操作できてしまってはいけない。盤面のタップは
      // session.tap 自身が isOver を見て無視するのに加え、重ね表示の
      // 不透明な Container がタップを物理的に奪うので二重に守られている。
      // やめるボタンは重ね表示の外(Stack の外)にあるので、ボタン自体を
      // 無効化していないと、終わった後にも「やめると今日のボーナスは
      // 終わりです」という(既に終わっているのに)誤解を招く確認が出せて
      // しまう。
      final session = await playToGameOver();
      await pumpGame(tester, session);
      final button =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'やめる'));
      expect(button.onPressed, isNull);
    });

    testWidgets('「結果へ」で結果画面に進む', (tester) async {
      final session = await playToGameOver();
      await pumpGame(tester, session);
      await tester.tap(find.text('結果へ'));
      await tester.pumpAndSettle();
      expect(find.byType(BonusResultScreen), findsOneWidget);
      expect(find.byType(BonusGridView), findsNothing);
    });

    testWidgets('クリアでは重ねずに直接結果画面へ行く', (tester) async {
      // クリアと「やめる」はプレイヤー自身の行為なので、なぜ終わったかを
      // 見せる段は要らない(仕様 §3.2)。
      final session = await sessionWith(gridOf([
        [9, 9, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]));
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
      await tester.pumpAndSettle();
      expect(find.byType(BonusResultScreen), findsOneWidget);
      expect(find.text('10 を作った!'), findsOneWidget);
      expect(find.text('結果へ'), findsNothing);
    });
  });

  group('結果画面の 3 状態', () {
    Future<void> pumpResult(WidgetTester tester, BonusOutcome outcome) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BonusResultScreen(
            score: 852,
            bestScore: 852,
            bestUpdated: true,
            isSaving: false,
            outcome: outcome,
            onHome: () {},
          ),
        ),
      );
    }

    testWidgets('クリア', (tester) async {
      await pumpResult(tester, BonusOutcome.cleared);
      expect(find.text('10 を作った!'), findsOneWidget);
      expect(find.text('ゲームオーバー'), findsNothing);
      expect(find.text('ここまで'), findsNothing);
    });

    testWidgets('ゲームオーバー', (tester) async {
      await pumpResult(tester, BonusOutcome.gameOver);
      expect(find.text('ゲームオーバー'), findsOneWidget);
      expect(find.text('10 を作った!'), findsNothing);
      expect(find.text('ここまで'), findsNothing);
    });

    testWidgets('やめた', (tester) async {
      await pumpResult(tester, BonusOutcome.gaveUp);
      expect(find.text('ここまで'), findsOneWidget);
      expect(find.text('10 を作った!'), findsNothing);
      expect(find.text('ゲームオーバー'), findsNothing);
    });

    testWidgets('どの終わり方でもスコアとベストは出る', (tester) async {
      for (final outcome in BonusOutcome.values) {
        await pumpResult(tester, outcome);
        expect(find.text('スコア 852'), findsOneWidget);
        expect(find.text('ベスト更新!'), findsOneWidget);
      }
    });
  });

  group('レイアウト', () {
    testWidgets('320pt 幅で溢れない', (tester) async {
      final session = await sessionWith(fiveTwosGrid(), repairsUsed: 7);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: BonusGameScreen(session: session, onExit: () {})),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
