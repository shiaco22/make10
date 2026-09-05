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

/// (1,0)(1,1)(1,2)(2,1)(2,2) の 2 が 5 マス連結する盤面。
BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

/// fiveTwosGrid() の左上だけを 10 にした盤面。「最大 10」を画面に
/// 出すためだけの盤面で、実際のプレイでは辿り着けない値
/// (10 は達成した瞬間にクリアになり、この画面から結果画面へ切り替わる
/// ため — lib/domain/bonus/bonus_grid.dart の tap() 参照)。それでも
/// 320pt 幅のレイアウトは「万一 2 桁の最大値を描いても崩れない」ことを
/// 保証すべきなので、防御的に最悪値として使う。
BonusGrid worstCaseDigitsGrid() => gridOf([
      [10, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

/// (0,0)(0,1) が 9 で、1 手でクリアできる盤面。
BonusGrid nearlyClearedGrid() => gridOf([
      [9, 9, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
    ]);

/// checkerboard の唯一の同値ペア (0,0)-(0,1) の 3 を合成すると、空きは
/// (0,1) の 1 マスだけになる。残りは checkerboard で合法手が無いので、
/// そこへの補充(乱数消費 1 回)が隣接マスと一致するかどうかだけで詰みが
/// 決まる -- `test/game/bonus_session_test.dart` の同名フィクスチャと同じ
/// 盤面で、`Random(0)`(このファイルの [sessionWith] が使う既定のシード)
/// では実測で必ず詰みが起きることをそちらのテストが独立に確認済み。
BonusGrid singleGapGrid() => gridOf([
      [3, 3, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
      [2, 1, 2, 1, 2],
      [1, 2, 1, 2, 1],
    ]);

Future<BonusSession> sessionWith(BonusGrid grid, {int score = 0}) async {
  final repo = BonusRepository();
  await repo.load();
  return BonusSession(
    repository: repo,
    grid: grid,
    score: score,
    random: Random(0),
  );
}

Future<void> pumpGame(
  WidgetTester tester,
  BonusSession session, {
  VoidCallback? onExit,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: BonusGameScreen(session: session, onExit: onExit ?? () {}),
    ),
  );
}

/// 確認ダイアログの「やめる」ボタン。画面下の「やめる」ボタンと同じ
/// 文字列なので、`find.text('やめる')` はダイアログが開いている間 2 件
/// ヒットする。順序(`.last`)に頼ると、Overlay の実装詳細が変われば
/// 静かに壊れて画面側のボタンを叩きかねないので、[AlertDialog] の子孫に
/// 明示的に絞る。
Finder dialogConfirmButton() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('やめる'),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('BonusGameScreen', () {
    testWidgets('盤面とスコアを出す', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      expect(find.byType(BonusGridView), findsOneWidget);
      expect(find.text('スコア 0'), findsOneWidget);
    });

    testWidgets('マスをタップするとスコア表示が更新される', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      expect(find.text('スコア 10'), findsOneWidget);
    });

    testWidgets('不正な手ではスコアが動かない', (tester) async {
      final grid = gridOf([
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
        [2, 1, 2, 1, 2],
        [1, 2, 1, 2, 1],
      ]);
      await pumpGame(tester, await sessionWith(grid));
      await tester.tap(find.byKey(const ValueKey('bonus-cell-12')));
      await tester.pump();
      expect(find.text('スコア 0'), findsOneWidget);
    });

    testWidgets('現在の最大値を出す', (tester) async {
      await pumpGame(tester, await sessionWith(nearlyClearedGrid()));
      expect(find.text('最大 9'), findsOneWidget);
    });

    testWidgets('やめるを押すと確認を出す', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()));
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日のボーナスは終わり'), findsOneWidget);
    });

    testWidgets('確認をキャンセルするとゲームが続く', (tester) async {
      final session = await sessionWith(fiveTwosGrid());
      await pumpGame(tester, session);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      expect(session.isOver, isFalse);
      expect(find.byType(BonusGridView), findsOneWidget);
    });

    testWidgets('確認を承諾すると結果画面になる', (tester) async {
      final session = await sessionWith(fiveTwosGrid());
      await pumpGame(tester, session);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      await tester.tap(dialogConfirmButton());
      await tester.pumpAndSettle();
      expect(session.isOver, isTrue);
      expect(find.byType(BonusResultScreen), findsOneWidget);
      // 途中でやめた場合は outcome: BonusOutcome.gaveUp が結果画面に
      // 伝わっているはず -- これを見ずに BonusResultScreen が出たことだけを
      // 確認すると、BonusGameScreen 側の `outcome: session.outcome!` の
      // 配線を `outcome: BonusOutcome.cleared` に固定する変異が入っても
      // 素通りしてしまう(確かめ済み: この配線を壊しても他のテストは
      // 全部通ったままだった)。
      expect(find.text('ここまで'), findsOneWidget);
      expect(find.text('10 を作った!'), findsNothing);
    });

    testWidgets('クリアすると結果画面に切り替わる', (tester) async {
      await pumpGame(tester, await sessionWith(nearlyClearedGrid()));
      await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
      await tester.pumpAndSettle();
      expect(find.byType(BonusResultScreen), findsOneWidget);
      expect(find.text('10 を作った!'), findsOneWidget);
    });

    testWidgets('詰みを修復したら通知を出す', (tester) async {
      // 詰みは 8 タップに 1 回起きる。無言で盤面が書き換わると理不尽に
      // 見えるので、修復したことが分かる表示を出す。singleGapGrid() を
      // このファイルの既定シード(Random(0))でタップ 0 すると、実測で
      // 必ず詰みが起きる(test/game/bonus_session_test.dart で独立に
      // 確認済みの、同じ盤面・同じシードでの事実)。前提が崩れていないか
      // 自体も確かめたうえで、通知の表示を無条件にアサートする --
      // 「修復が起きたときだけ確認する」if ガードは、修復が起きなくても
      // 静かに素通りしてしまう。
      //
      // 'マス入れ替えました' まで絞るのは、残り回数の常時表示
      // (`入れ替え N`)も 'textContaining入れ替え' に引っかかるようになった
      // ため -- 単なる '入れ替え' では 2 件ヒットして findsOneWidget が
      // 壊れる(仕様 §3.3 で残り回数を常時表示にした結果の衝突)。
      final session = await sessionWith(singleGapGrid());
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
      await tester.pump();
      expect(session.lastRepairedCells, greaterThan(0),
          reason: '前提が崩れている: このシードでは詰みが起きるはず'
              '(test/game/bonus_session_test.dart 参照)');
      expect(find.textContaining('マス入れ替えました'), findsOneWidget);
    });

    testWidgets('320pt 幅で溢れない', (tester) async {
      // 現実的な最悪値で試す: スコアは 4 桁(中央値は ~850、p90 は ~1060
      // なので普通に起こりうる — tool/simulate_bonus.dart の実測)、
      // 最大値と入れ替えの残りはどちらも 2 桁(入れ替えはゲーム開始
      // 直後から kBonusRepairLimit の 10)。
      //
      // fiveTwosGrid() + score: 0(既定値)のままでは、スコアが 1 桁に
      // 収まってしまい溢れが再現しない — この場合ここは「たまたま
      // 選んだ値では溢れない」ことしか確認しておらず、「320pt 幅で
      // 溢れない」という主張自体は検査できていなかった。
      await pumpGame(
        tester,
        await sessionWith(worstCaseDigitsGrid(), score: 9999),
        size: const Size(320, 480),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('タブレット幅でも溢れない', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()),
          size: const Size(820, 1180));
      expect(tester.takeException(), isNull);
    });

    testWidgets('横向きでも溢れない', (tester) async {
      await pumpGame(tester, await sessionWith(fiveTwosGrid()),
          size: const Size(1180, 820));
      expect(tester.takeException(), isNull);
    });
  });

  group('BonusResultScreen', () {
    Future<void> pumpResult(
      WidgetTester tester, {
      required int score,
      required int bestScore,
      required bool bestUpdated,
      required bool isSaving,
      required bool cleared,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BonusResultScreen(
            score: score,
            bestScore: bestScore,
            bestUpdated: bestUpdated,
            isSaving: isSaving,
            outcome: cleared ? BonusOutcome.cleared : BonusOutcome.gaveUp,
            onHome: () {},
          ),
        ),
      );
    }

    testWidgets('スコアとベストを出す', (tester) async {
      await pumpResult(tester,
          score: 994,
          bestScore: 1220,
          bestUpdated: false,
          isSaving: false,
          cleared: true);
      expect(find.text('スコア 994'), findsOneWidget);
      expect(find.text('ベスト 1220'), findsOneWidget);
    });

    testWidgets('ベスト更新を出す', (tester) async {
      await pumpResult(tester,
          score: 1300,
          bestScore: 1300,
          bestUpdated: true,
          isSaving: false,
          cleared: true);
      expect(find.text('ベスト更新!'), findsOneWidget);
    });

    testWidgets('保存中はベスト行を伏せる', (tester) async {
      // 保存が終わる前に描くと、古いベストが一瞬出てから「ベスト更新!」に
      // 切り替わってちらつく(既存 ResultScreen と同じ理由)。
      await pumpResult(tester,
          score: 1300,
          bestScore: 900,
          bestUpdated: false,
          isSaving: true,
          cleared: true);
      expect(find.text('ベスト 900'), findsNothing);
      expect(find.text('ベスト更新!'), findsNothing);
      expect(find.text('スコア 1300'), findsOneWidget);
    });

    testWidgets('クリアと途中終了で見出しが違う', (tester) async {
      await pumpResult(tester,
          score: 100,
          bestScore: 100,
          bestUpdated: true,
          isSaving: false,
          cleared: true);
      expect(find.text('10 を作った!'), findsOneWidget);

      await pumpResult(tester,
          score: 100,
          bestScore: 100,
          bestUpdated: true,
          isSaving: false,
          cleared: false);
      expect(find.text('10 を作った!'), findsNothing);
      expect(find.text('ここまで'), findsOneWidget);
    });

    testWidgets('また明日と伝える', (tester) async {
      await pumpResult(tester,
          score: 100,
          bestScore: 100,
          bestUpdated: true,
          isSaving: false,
          cleared: true);
      expect(find.textContaining('また明日'), findsOneWidget);
    });
  });
}
