import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
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
}
