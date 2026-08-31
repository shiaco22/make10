import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/game/time_attack_session.dart';
import 'package:make10/ui/time_attack_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';

void main() {
  late StatsRepository stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stats = StatsRepository();
    await stats.load();
  });

  testWidgets('shows the remaining time', (tester) async {
    final ta = await timeAttackWith(stats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    expect(find.text('2:00'), findsOneWidget);
  });

  testWidgets('hint and answer are disabled', (tester) async {
    final ta = await timeAttackWith(stats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    final hint = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('ヒント'),
        matching: find.byType(TextButton),
      ),
    );
    expect(hint.onPressed, isNull);
    final answer = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('答え'),
        matching: find.byType(TextButton),
      ),
    );
    expect(answer.onPressed, isNull);
  });

  testWidgets('the clock display follows the session', (tester) async {
    // Ticker の実時間に頼らず tick を直接呼ぶ。表示の追従だけを見る。
    final ta = await timeAttackWith(stats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    ta.tick(const Duration(seconds: 30));
    await tester.pump();
    expect(find.text('1:30'), findsOneWidget);
  });

  testWidgets('the result screen appears when time runs out', (tester) async {
    final ta = await timeAttackWith(stats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    ta.tick(kTimeAttackDuration);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('スコア'), findsOneWidget);
    expect(find.text('もう一度'), findsOneWidget);
  });

  testWidgets('tapping retry calls onRetry but not onExit', (tester) async {
    final ta = await timeAttackWith(stats);
    var retried = false;
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(
        session: ta,
        onExit: () => exited = true,
        onRetry: () => retried = true,
      ),
    ));
    ta.tick(kTimeAttackDuration);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('もう一度'));
    await tester.pump();

    expect(retried, isTrue);
    expect(exited, isFalse);
  });

  testWidgets('tapping home calls onExit but not onRetry', (tester) async {
    final ta = await timeAttackWith(stats);
    var retried = false;
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(
        session: ta,
        onExit: () => exited = true,
        onRetry: () => retried = true,
      ),
    ));
    ta.tick(kTimeAttackDuration);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('ホームへ'));
    await tester.pump();

    expect(exited, isTrue);
    expect(retried, isFalse);
  });

  testWidgets(
      'the retry button still renders and falls back to onExit when onRetry is omitted',
      (tester) async {
    final ta = await timeAttackWith(stats);
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(
        session: ta,
        onExit: () => exited = true,
      ),
    ));
    ta.tick(kTimeAttackDuration);
    await tester.pump();
    await tester.pump();

    expect(find.text('もう一度'), findsOneWidget);

    await tester.tap(find.text('もう一度'));
    await tester.pump();

    expect(exited, isTrue);
  });

  testWidgets('a new best score shows ベスト更新 instead of the best line',
      (tester) async {
    final ta = await timeAttackWith(stats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    playSolution(ta.session); // score: 0 -> 1, beats the starting best of 0
    ta.tick(kTimeAttackDuration);
    await tester.pump();
    await tester.pump();

    expect(find.text('ベスト更新!'), findsOneWidget);
    expect(find.text('ベスト 1'), findsNothing);
  });

  testWidgets('a tied score shows the best line, not ベスト更新', (tester) async {
    final ta = await timeAttackWith(stats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    // 何もクリアせずに時間切れにする。スコアは 0 のまま、開始時のベストも 0
    // なので、recordTimeAttack の「厳密に大きい」判定では更新にならない。
    ta.tick(kTimeAttackDuration);
    await tester.pump();
    await tester.pump();

    expect(find.text('ベスト 0'), findsOneWidget);
    expect(find.text('ベスト更新!'), findsNothing);
  });

  testWidgets('a worse score keeps showing the previous best', (tester) async {
    // StatsRepository._save() が書き込む JSON と同じ形を再現してシードする。
    // キーは prefsKey 'make10.stats'。setMockInitialValues は 'flutter.' で
    // 始まらないキーを自動的に 'flutter.' プレフィックス付きに変換するので、
    // ここではプレフィックスなしのキーを渡す。
    final seeded = jsonEncode({
      'version': 1,
      'practice': {
        for (final d in Difficulty.values)
          d.key: {
            'solved': 0,
            'totalTimeMs': 0,
            'hintUsed': 0,
            'answerShown': 0,
            'skipped': 0,
          },
      },
      'timeAttack': {
        for (final d in Difficulty.values)
          d.key: d == Difficulty.normal
              ? {'bestScore': 10, 'playCount': 1}
              : {'bestScore': 0, 'playCount': 0},
      },
    });
    SharedPreferences.setMockInitialValues({'make10.stats': seeded});
    final seededStats = StatsRepository();
    await seededStats.load();
    expect(seededStats.timeAttack(Difficulty.normal).bestScore, 10);

    final ta = await timeAttackWith(seededStats);
    await tester.pumpWidget(MaterialApp(
      home: TimeAttackScreen(session: ta, onExit: () {}),
    ));
    ta.tick(kTimeAttackDuration); // 何もクリアしない、スコアは 0 のまま
    await tester.pump();
    await tester.pump();

    expect(find.text('ベスト 10'), findsOneWidget);
    expect(find.text('スコア 0'), findsOneWidget);
  });
}
