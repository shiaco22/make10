import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:make10/game/time_attack_session.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:make10/ui/result_screen.dart';
import 'package:make10/ui/time_attack_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

String today() => bonusDateKey(DateTime.now());

Future<BonusRepository> loadedRepo() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

/// app_boot_test.dart / interstitial_wiring_test.dart と同じ理由: rootBundle
/// は assets/puzzles.json の loadString の Future をプロセス全体で
/// キャッシュするので、テストごとに evict しないと 2 つ目以降が
/// pumpAndSettle で無限に固まる。
Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 40,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('_pumpUntilGone: still present after $maxTries tries');
}

/// TimeAttackScreen の Ticker は isOver になるまでフレームを出し続けるので、
/// 通常の画面遷移待ちに pumpAndSettle は使えない(interstitial_wiring_test.dart
/// 参照)。
Future<void> _pumpTransition(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.evict('assets/puzzles.json');
  });

  group('解禁の判定', () {
    test('5 問で解禁する', () async {
      final repo = await loadedRepo();
      expect(5 >= kBonusUnlockClears, isTrue);
      expect(await repo.earn(today()), isTrue);
      expect(repo.ticket.isAvailable(today()), isTrue);
    });

    test('4 問では解禁しない（呼び出し側が earn を呼ばない）', () async {
      final repo = await loadedRepo();
      expect(4 >= kBonusUnlockClears, isFalse);
      expect(repo.ticket.isAvailable(today()), isFalse);
    });

    test('今日の上限まで獲得済みなら増えない', () async {
      // 「その日すでに遊んでいれば5問でも解禁しない」という旧テストは
      // ここにあった。回数制ではまさに逆になる — 遊んだ後でも5問クリア
      // すればまた増える — ので削除して置き換える(計画 Task 4 Step 5)。
      final repo = await loadedRepo();
      for (var i = 0; i < kBonusPlaysPerDay; i++) {
        expect(await repo.earn(today()), isTrue);
      }
      expect(await repo.earn(today()), isFalse);
      expect(repo.ticket.earned, kBonusPlaysPerDay);
    });
  });

  group('ResultScreen の告知スロット', () {
    Future<void> pump(WidgetTester tester, {Widget? notice}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            score: 6,
            bestScore: 6,
            bestUpdated: true,
            isSaving: false,
            notice: notice,
            onRetry: () {},
            onHome: () {},
          ),
        ),
      );
    }

    testWidgets('notice を渡すと表示される', (tester) async {
      await pump(tester, notice: const Text('ボーナスゲーム解禁!'));
      expect(find.text('ボーナスゲーム解禁!'), findsOneWidget);
    });

    testWidgets('notice を渡さなければ今日通りの表示', (tester) async {
      await pump(tester);
      expect(find.text('スコア 6'), findsOneWidget);
      expect(find.text('ベスト更新!'), findsOneWidget);
      expect(find.text('もう一度'), findsOneWidget);
      expect(find.text('ホームへ'), findsOneWidget);
    });
  });

  group('TimeAttackScreen.onFinished フック', () {
    late StatsRepository stats;
    setUp(() async {
      stats = StatsRepository();
      await stats.load();
    });

    testWidgets('5 問以上のクリアで一度だけ呼ばれる（rebuild のたびにではない）',
        (tester) async {
      // build は AnimatedBuilder の中にあり、リザルト表示中も
      // notifyListeners のたびに何度も走る(保存の完了自体がそう)。
      // ガードが無ければ、その再 build のたびに onFinished が呼ばれて
      // しまう(earn 自体は呼び直しても実害が無い設計だが、フックの
      // 二重発火はそれとは別の潜在バグ)。
      final ta = await timeAttackWith(stats);
      var callCount = 0;
      var lastScore = -1;
      await tester.pumpWidget(MaterialApp(
        home: TimeAttackScreen(
          session: ta,
          onExit: () {},
          onFinished: (score) async {
            callCount++;
            lastScore = score;
          },
        ),
      ));

      for (var i = 0; i < 5; i++) {
        playSolution(ta.session);
        await tester.pump();
      }

      ta.tick(kTimeAttackDuration);
      // isOver が初めて true になる build。
      await tester.pump();
      // 結果の保存(StatsRepository 経由)が確定して notifyListeners が飛ぶと
      // AnimatedBuilder がもう一度 build を走らせる。
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(callCount, 1, reason: '最初の build で onFinished が呼ばれていない');
      expect(lastScore, 5);

      // モックの SharedPreferences は実機よりずっと速く解決するため、
      // 保存完了に伴う 2 回目の notifyListeners が上の pump 列の**どこかの
      // 1 フレームに自然に収まってしまい**、isOver のまま独立した 2 回目の
      // build が観測できない(確認済み: ガードを外しても上のアサーションは
      // 通ってしまい、このテストの本来の主張を検証できていなかった)。
      // isOver のまま build が再度走る状況そのものを直接作って確かめる。
      ta.notifyListeners();
      await tester.pump();

      expect(callCount, 1,
          reason: 'onFinished が isOver になった後の再 build で再び呼ばれた');
    });
  });

  group('実際の配線を通した解禁判定', () {
    // Task 12 の計画のテストは BonusTicket / BonusRepository を直接呼ぶ
    // ドメインレベルのテストが中心で、それは Task 5 で既にカバーされている
    // (上の「解禁の判定」グループがその重複)。ここでは
    // HomeScreen._startTimeAttack の onFinished 配線と
    // BonusEarnNotice の表示を、実際の画面遷移を通して確認する。
    Future<void> bootToHome(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: HomeScreen())),
      );
      await _pumpUntilGone(tester, find.byType(CircularProgressIndicator));
    }

    Future<TimeAttackSession> startTimeAttackFromHome(
      WidgetTester tester, {
      String label = 'ふつう',
    }) async {
      await tester.tap(find.widgetWithText(FilledButton, 'タイムアタック'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await _pumpTransition(tester);
      return tester
          .widget<TimeAttackScreen>(find.byType(TimeAttackScreen))
          .session;
    }

    testWidgets('4問では実際の配線を通しても解禁されない', (tester) async {
      await bootToHome(tester);
      final ta = await startTimeAttackFromHome(tester);

      for (var i = 0; i < 4; i++) {
        playSolution(ta.session);
        await tester.pump();
      }
      ta.tick(kTimeAttackDuration);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('ボーナスゲーム +1回'), findsNothing);

      await tester.tap(find.text('ホームへ'));
      await tester.pumpAndSettle();

      expect(find.textContaining('タイムアタックで'), findsOneWidget,
          reason: '4 問クリアなのにボーナスが解禁された表示になっている');
      expect(find.text('★ ボーナスゲーム'), findsNothing);
    });

    testWidgets('5問なら実際の配線を通して解禁される', (tester) async {
      await bootToHome(tester);
      final ta = await startTimeAttackFromHome(tester);

      for (var i = 0; i < 5; i++) {
        playSolution(ta.session);
        await tester.pump();
      }
      ta.tick(kTimeAttackDuration);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('ボーナスゲーム +1回'), findsOneWidget);

      await tester.tap(find.text('ホームへ'));
      await tester.pumpAndSettle();

      expect(find.text('★ ボーナスゲーム（あと 1 回）'), findsOneWidget,
          reason: '5 問クリアしたのにボーナスが解禁されていない');
    });

    testWidgets('今日の上限まで獲得済みなら5問クリアしても告知が出ない', (tester) async {
      // Task 4 Step 7 の変異検査の要となるテスト。BonusEarnNotice を直接
      // 組み立てる bonus_earn_notice_test.dart は onFinished の配線自体を
      // 通らないため、home_screen.dart 側の
      // 「if (!await bonus.earn(today)) return;」を
      // 「await bonus.earn(today);」に変異させても検出できない
      // (計画のコメントが明示的に警告している穴)。実際の
      // HomeScreen -> TimeAttackScreen の配線を通し、今日の上限まで
      // 獲得済みの状態から5問クリアしても告知が出ないことをここで見る。
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({
          'version': 2,
          'bestScore': 0,
          'day': today(),
          'earned': kBonusPlaysPerDay,
          'played': kBonusPlaysPerDay,
        }),
      });
      await bootToHome(tester);
      final ta = await startTimeAttackFromHome(tester);

      for (var i = 0; i < 5; i++) {
        playSolution(ta.session);
        await tester.pump();
      }
      ta.tick(kTimeAttackDuration);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('ボーナスゲーム +1回'), findsNothing,
          reason: '今日の上限に達しているのに獲得の告知が出ている');
      expect(find.textContaining('遊べます'), findsNothing);
    });
  });
}
