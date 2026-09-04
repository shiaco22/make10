import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:make10/ui/bonus_game_screen.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

String today() => bonusDateKey(DateTime.now());
String yesterday() =>
    bonusDateKey(DateTime.now().subtract(const Duration(days: 1)));

/// 25 マスの合法な盤面（1 が隣接している）。
List<int> playableCells() => [
      1, 1, 3, 1, 2,
      3, 1, 2, 3, 1,
      2, 3, 1, 2, 3,
      1, 2, 3, 1, 2,
      3, 1, 2, 3, 1,
    ];

void setBonusPrefs({
  int bestScore = 0,
  String? unlockedOn,
  String? playedOn,
  bool inProgress = false,
  int inProgressScore = 0,
}) {
  SharedPreferences.setMockInitialValues({
    'make10.bonus': jsonEncode({
      'version': 1,
      'bestScore': bestScore,
      'unlockedOn': unlockedOn,
      'playedOn': playedOn,
      if (inProgress)
        'inProgress': {'grid': playableCells(), 'score': inProgressScore},
    }),
  });
}

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: HomeScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // rootBundle は プロセス全体で 1 つのキャッシュを持ち、loadString の
    // Future をアセットキーごとに使い回す。このファイルは 1 テストごとに
    // 新しい ProviderScope 越しに puzzleRepositoryProvider（内部で
    // assets/puzzles.json を読む）を作り直すが、前のテストのゾーンで
    // 生成・完了した Future を後のテストのゾーンで await しても解決しない
    // ため、evict せずにいると 2 テスト目以降が pumpHome の
    // pumpAndSettle で無限に固まる（app_boot_test.dart のコメント参照）。
    rootBundle.evict('assets/puzzles.json');
  });

  group('ホーム画面のボーナス入口', () {
    testWidgets('未解禁では条件を出し、押せない', (tester) async {
      // 未解禁でも隠さない。メカニクスを知らせる導線になり、
      // タイムアタックを遊ぶ理由にもなる（仕様 §7.1）。
      setBonusPrefs();
      await pumpHome(tester);
      expect(
        find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
        findsOneWidget,
      );
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('タイムアタックで'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull, reason: '未解禁なのに押せる');
    });

    testWidgets('解禁済みでは押せる', (tester) async {
      setBonusPrefs(unlockedOn: today());
      await pumpHome(tester);
      expect(find.text('★ ボーナスゲーム'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('★ ボーナスゲーム'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull, reason: '解禁済みなのに押せない');
    });

    testWidgets('本日終了ではベストを出し、押せない', (tester) async {
      setBonusPrefs(bestScore: 994, unlockedOn: today(), playedOn: today());
      await pumpHome(tester);
      expect(find.text('ボーナスゲーム（また明日） ベスト 994'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('また明日'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('中断があれば続きから遊べる', (tester) async {
      // 権利は開始時に消費済みなので playedOn は今日。それでも未完了の
      // 盤面があれば再開できる（仕様 §4.3）。
      setBonusPrefs(
        unlockedOn: today(),
        playedOn: today(),
        inProgress: true,
        inProgressScore: 340,
      );
      await pumpHome(tester);
      expect(find.text('ボーナスゲーム（続きから）'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.textContaining('続きから'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('前日に解禁して遊ばなかった権利は消えている', (tester) async {
      setBonusPrefs(unlockedOn: yesterday());
      await pumpHome(tester);
      expect(find.textContaining('タイムアタックで'), findsOneWidget);
      expect(find.text('★ ボーナスゲーム'), findsNothing);
    });

    testWidgets('前日に遊んでいても今日の未解禁表示になる', (tester) async {
      setBonusPrefs(
          bestScore: 500, unlockedOn: yesterday(), playedOn: yesterday());
      await pumpHome(tester);
      expect(find.textContaining('タイムアタックで'), findsOneWidget);
      expect(find.textContaining('また明日'), findsNothing);
    });

    testWidgets('解禁済みから押すとゲーム画面へ進む', (tester) async {
      setBonusPrefs(unlockedOn: today());
      await pumpHome(tester);
      await tester.tap(find.text('★ ボーナスゲーム'));
      await tester.pumpAndSettle();
      expect(find.byType(BonusGridView), findsOneWidget);
    });

    testWidgets('中断から押すとスコアを引き継いで再開する', (tester) async {
      setBonusPrefs(
        unlockedOn: today(),
        playedOn: today(),
        inProgress: true,
        inProgressScore: 340,
      );
      await pumpHome(tester);
      await tester.tap(find.textContaining('続きから'));
      await tester.pumpAndSettle();
      expect(find.text('スコア 340'), findsOneWidget);
    });

    testWidgets('既存の 3 つの入口は残っている', (tester) async {
      setBonusPrefs();
      await pumpHome(tester);
      expect(find.text('プラクティス'), findsOneWidget);
      expect(find.text('タイムアタック'), findsOneWidget);
      expect(find.text('統計'), findsOneWidget);
    });

    testWidgets('連打しても BonusGameScreen が二重に積まれない', (tester) async {
      // BonusRepository.startGame は権利の消費と inProgressGrid の設定を
      // 内部の await より前（同期区間）で終える。ガードが無いと、1 回目の
      // タップがその await で止まっている間に来た 2 回目のタップは
      // 「中断あり」に見えて resumed 分岐に入り、1 回目とは独立した
      // BonusSession を新たに作って BonusGameScreen をもう一つ積んでしまう
      // -- 権利は消費されないが、同じ盤面を指す 2 つの独立したセッションが
      // 並存し、どちらを操作するかで保存されるスコアが食い違う。
      //
      // tester.tap を 2 回連続で await せずに呼ぶことはできない
      // (TestAsyncUtils が「await し忘れ」として弾く) ため、
      // ウィジェットから直接取り出した onPressed を、間に await を挟まず
      // 同期的に 2 回呼んで、まさにこの競合状態を再現する。
      setBonusPrefs(unlockedOn: today());
      await pumpHome(tester);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('★ ボーナスゲーム'),
          matching: find.byType(TextButton),
        ),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pumpAndSettle();
      // find.byType は使わない -- Navigator は下敷きになった
      // MaterialPageRoute (opaque) を Offstage 相当の扱いにしてしまい、
      // find の走査から見えなくなる。そのため二重に積んでいても
      // find.byType(BonusGridView) は 1 のまま変わらず、この回帰を
      // 検出できない(実際に確認した: ガードを外すと tester.allWidgets
      // 経由では 2 つ見えるのに find.byType は 1 のままだった)。
      // ツリーそのものを舐める allWidgets で数える。
      expect(
        tester.allWidgets.whereType<BonusGameScreen>().length,
        1,
        reason: '連打で BonusGameScreen が二重に積まれた',
      );
    });
  });
}
