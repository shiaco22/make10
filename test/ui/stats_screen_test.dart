import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/ui/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a dash for the average before any clear', (tester) async {
    final stats = StatsRepository();
    await stats.load();
    await tester.pumpWidget(MaterialApp(home: StatsScreen(stats: stats)));
    // 「平均 -」が難易度 3 つ分並ぶ。
    expect(find.text('平均 -'), findsNWidgets(3));
  });

  testWidgets('shows every recorded counter', (tester) async {
    final stats = StatsRepository();
    await stats.load();
    await stats.recordSolved(Difficulty.hard, elapsedMs: 8000, usedHint: true);
    await stats.recordAnswerShown(Difficulty.hard);
    await stats.recordSkipped(Difficulty.hard);
    await stats.recordTimeAttack(Difficulty.hard, 4);

    await tester.pumpWidget(MaterialApp(home: StatsScreen(stats: stats)));
    expect(find.text('むずかしい'), findsOneWidget);
    expect(find.textContaining('クリア 1'), findsOneWidget);
    expect(find.textContaining('ヒント 1'), findsOneWidget);
    expect(find.textContaining('答え 1'), findsOneWidget);
    expect(find.textContaining('スキップ 1'), findsOneWidget);
    expect(find.textContaining('ベスト 4'), findsOneWidget);
  });
}
