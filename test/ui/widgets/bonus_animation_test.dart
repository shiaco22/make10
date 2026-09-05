import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/game/bonus_session.dart';
import 'package:make10/ui/bonus_game_screen.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

/// (1,0)(1,1)(1,2)(2,1)(2,2) の 2 が 5 マス連結する。
BonusGrid fiveTwosGrid() => gridOf([
      [1, 3, 1, 3, 1],
      [2, 2, 2, 3, 1],
      [3, 2, 2, 1, 3],
      [1, 3, 1, 3, 1],
      [3, 1, 3, 1, 3],
    ]);

Future<BonusSession> makeSession({int seed = 0, int repairsUsed = 0}) async {
  final repo = BonusRepository();
  await repo.load();
  return BonusSession(
    repository: repo,
    grid: fiveTwosGrid(),
    score: 0,
    repairsUsed: repairsUsed,
    random: Random(seed),
  );
}

Future<void> pumpGame(
  WidgetTester tester,
  BonusSession session, {
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: BonusGameScreen(session: session, onExit: () {}),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('論理状態はアニメーションを待たない', () {
    testWidgets('タップした直後にスコアが確定する', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      // pump を 1 フレームだけ。アニメーションはまだ終わっていない。
      await tester.pump();
      expect(session.score, 10);
      expect(find.text('スコア 10'), findsOneWidget);
    });

    testWidgets('アニメーション中のタップが受け付けられる', (tester) async {
      // 92 タップのゲームで 1 手ごとに 300ms 待たせると 28 秒の待ち時間に
      // なる。連打しても手が落ちないことが要点(仕様 §4.1)。
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60)); // 消滅の途中
      final mid = session.score;

      // 打てるマスを探して、もう 1 手打つ。
      final next = [
        for (var i = 0; i < kBonusCells; i++)
          if (session.grid.canTap(i)) i,
      ].first;
      await tester.tap(find.byKey(ValueKey('bonus-cell-$next')));
      await tester.pump();
      expect(session.score, greaterThan(mid),
          reason: 'アニメーション中のタップが捨てられている');
      await tester.pumpAndSettle();
    });
  });

  group('アニメーションの尺', () {
    testWidgets('300ms で落ち着く', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      // 合計 300ms(消滅 120 + 落下 180)。手動で 1 回だけ大きく pump すると
      // 落ちる -- Ticker は「実際に最初の tick が来た瞬間」を基準時刻
      // (_startTime)にするので、tap 直後の 1 回目の pump(forward() が
      // 呼ばれる pump)の次に来る pump が Ticker にとって最初の tick になり、
      // そこでの経過時間は(どれだけ長い Duration を渡しても)常に 0 に
      // なる -- 何ミリ秒進めたつもりでも、基準点そのものをその場で決めて
      // いるだけなので進捗が出ない(実測で確認済み)。pumpAndSettle で
      // フレームが尽きるまで確実に進めれば、この事情に関係なく安定して
      // 検査できる。
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'pumpAndSettle してもアニメーションが続いている');
    });

    // 上のテストだけでは「アニメーションが実際に 300ms かけて動いている
    // こと」を確認できない -- didUpdateWidget の
    // `_controller.forward(from: 0)` を `_controller.value = 1.0`(即座に
    // 最終状態へ飛ぶ)へ差し替えても、pumpAndSettle 後にはどちらも
    // hasScheduledFrame が false になるので、上のテストはこの変異を検出
    // しない(実際に差し替えて確認済み)。
    //
    // hasScheduledFrame で「始まったこと」を見分ける案も試したが、
    // タップした InkWell 自身のインクスプラッシュが無関係に Ticker を
    // 使うため、`.value = 1.0` に差し替えても tap 直後は
    // hasScheduledFrame が true のままで、この変異を検出できなかった
    // (実測して確認済み)。
    //
    // 代わりに、盤面の値そのもの(_controller.value)を見分ける:
    // `forward(from: 0)` は値を 0 にしてから Ticker を起動するので、
    // タップして 1 回だけ pump した直後はまだ t=0 のはず(Ticker の最初の
    // tick は次のフレームまで来ない)。t=0 なら消滅の幽霊がまだ残っている
    // ので、この時点で幽霊が「もう無い」ことは `.value = 1.0` へ即座に
    // 飛んでいることの実測的な証拠になる。
    testWidgets('タップ直後はまだ t=0(即座に最終状態へ飛んでいない)',
        (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      final ghostLayer = find.descendant(
        of: find.byType(BonusGridView),
        matching: find.byType(IgnorePointer),
      );
      expect(ghostLayer, findsOneWidget,
          reason: 'タップした直後なのに幽霊(消滅演出)がもう無い -- '
              '即座に最終状態へ飛んでいて、実際には何もアニメーションして '
              'いない可能性がある');
      await tester.pumpAndSettle();
    });
  });

  group('disableAnimations', () {
    testWidgets('立っていればアニメーションを飛ばす', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session, disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump();
      // hasScheduledFrame では検査しない -- タップした InkWell 自身の
      // インクスプラッシュ(Material の波紋)も無関係に Ticker を使って
      // 数フレーム スケジュールするため、disableAnimations の有無に
      // かかわらず true になり得る(実測で確認済み)。ここでは盤面自体の
      // アニメーションが飛ばされたことを直接見る: 飛ばされていれば
      // _controller.value が即座に 1.0 になり、vanishT も即座に 1.0 に
      // なるので、消滅アニメーション中だけ現れる幽霊レイヤーがこの
      // 時点で 1 つも無いはず。
      final ghostLayer = find.descendant(
        of: find.byType(BonusGridView),
        matching: find.byType(IgnorePointer),
      );
      expect(ghostLayer, findsNothing,
          reason: 'disableAnimations なのに幽霊(消滅演出)が残っている');
      expect(session.score, 10);
      await tester.pumpAndSettle();
    });
  });

  group('レイアウトの安全網', () {
    testWidgets('アニメーション中でも 320pt で溢れない', (tester) async {
      // repairsUsed: 7(残り 3)にしておく -- 既定の 0(残り 10)のままタップ
      // すると、スコアが "10" になった瞬間にスコアと残り回数の両方が
      // 2 桁になり、320pt でスコア行(スコア/最大/入れ替え)自体が溢れる
      // (実測: 右へ 13px)。これはこのタスクのアニメーションが引き起こす
      // ものではなく、Task 5 で作られたスコア行のフォントサイズに元から
      // あった余白の狭さ(既存の "320pt 幅で溢れない" テストは残り回数を
      // 1 桁のまま保つことでこの余白の狭さを踏んでいない)。このテストの
      // 目的はあくまで「アニメーションが新しい溢れを持ち込まないこと」
      // なので、既存テストと同じ 1 桁の残り回数に合わせる。
      final session = await makeSession(repairsUsed: 7);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: BonusGameScreen(session: session, onExit: () {})),
      );
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('アニメーション中も全マスがタップできる', (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60));
      for (var i = 0; i < kBonusCells; i++) {
        expect(find.byKey(ValueKey('bonus-cell-$i')), findsOneWidget,
            reason: 'アニメーション中に添字 $i のマスが消えている');
      }
      await tester.pumpAndSettle();
    });
  });

  group('幽霊レイヤー(消えたマスの表示)', () {
    testWidgets('消滅の途中は幽霊が実際に描かれている(0 サイズに潰れていない)',
        (tester) async {
      final session = await makeSession();
      await pumpGame(tester, session);
      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60)); // 消滅の途中

      // 幽霊レイヤーは(タップを奪わないよう)IgnorePointer で包まれている。
      // このテストは「幽霊レイヤーが盤面いっぱいの領域を実際に占めている
      // こと」を検査する。念のため書いておくと、`Positioned.fill` を
      // 外す変異は実際に試したが、この Flutter 版では RenderStack が
      // 非配置の子を持たない場合に受け取った制約の上限へ広がる仕様の
      // ため、このテストは落ちなかった(詳しい経緯は bonus_grid_view.dart
      // の Positioned.fill 周りのコメント参照)。`Positioned.fill` は
      // その実装詳細に依存しないための保険として残してあるが、この
      // テスト自体は「幽霊がちゃんと盤面いっぱいに描けている」ことの
      // 一般的な回帰検査として意味を持つ。
      //
      // `find.byType(IgnorePointer)` を画面全体に対して素朴に使うと、
      // MaterialApp が(ModalRoute のオフステージ処理などで)内部的に
      // 使っている無関係な IgnorePointer まで拾ってしまう(実測: このアプリ
      // では他に 3 件ヒットした)。BonusGridView の子孫に絞る。
      final ghostLayer = find.descendant(
        of: find.byType(BonusGridView),
        matching: find.byType(IgnorePointer),
      );
      expect(ghostLayer, findsOneWidget,
          reason: '消滅の途中なのに幽霊レイヤーが見つからない');

      final boardSize = tester.getSize(find.byType(BonusGridView));
      final ghostSize = tester.getSize(ghostLayer);
      expect(ghostSize.width, greaterThan(0));
      expect(ghostSize.height, greaterThan(0));
      expect(ghostSize, boardSize,
          reason: '幽霊レイヤーが盤面いっぱいの大きさになっていない '
              '(Positioned.fill が効いていない可能性がある)');

      await tester.pumpAndSettle();
    });

    testWidgets('幽霊は消えたマスの数だけ、消える前の値で表示される', (tester) async {
      // fiveTwosGrid() の index 5 をタップすると、連結成分 {5,6,7,11,12}
      // のうち {6,7,11,12} の 4 マスが消える(5 はタップ地点として残り
      // n+1 になる)。連結成分は全部同じ値(2)なので、幽霊も全部 "2"。
      //
      // 画面全体を `find.text('2')` で数えてはいけない -- 補充で新しく
      // 湧いたマスの値は乱数で決まるので、たまたま "2" になったマスが
      // 実盤面側にも現れることがある(実測: このシードでは 4 ではなく 7 件
      // ヒットした)。幽霊レイヤーの子孫だけに絞って数える。
      final session = await makeSession();
      await pumpGame(tester, session);

      // 前提の確認(乱数を消費しない読み取り専用の呼び出し -- removedCells
      // と mergedValue は補充に使う乱数と無関係に決まる)。
      final probe = session.grid.tap(5, Random(0));
      expect(probe, isNotNull);
      expect(probe!.removedCells, {6, 7, 11, 12});
      expect(probe.mergedValue, 2);

      await tester.tap(find.byKey(const ValueKey('bonus-cell-5')));
      await tester.pump(const Duration(milliseconds: 60)); // 消滅の途中

      final ghostLayer = find.descendant(
        of: find.byType(BonusGridView),
        matching: find.byType(IgnorePointer),
      );
      final ghostTiles = find.descendant(
        of: ghostLayer,
        matching: find.byType(BonusCellTile),
      );
      expect(ghostTiles, findsNWidgets(4), reason: '幽霊の数が消えたマスの数と違う');
      for (final tile in tester.widgetList<BonusCellTile>(ghostTiles)) {
        expect(tile.value, 2, reason: '幽霊が消える前の値(2)で表示されていない');
      }

      await tester.pumpAndSettle();
    });
  });
}
