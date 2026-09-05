import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:make10/ui/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpStats(WidgetTester tester, {required bool withBonus}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final stats = StatsRepository();
  await stats.load();
  BonusRepository? bonus;
  if (withBonus) {
    bonus = BonusRepository();
    await bonus.load();
  }
  await tester.pumpWidget(
    MaterialApp(home: StatsScreen(stats: stats, bonus: bonus)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ボーナスのベストスコアを出す', (tester) async {
    SharedPreferences.setMockInitialValues({
      'make10.bonus': jsonEncode({'version': 1, 'bestScore': 1220}),
    });
    await pumpStats(tester, withBonus: true);
    expect(find.text('ボーナスゲーム'), findsOneWidget);
    expect(find.text('ベスト 1220 点'), findsOneWidget);
  });

  testWidgets('まだ遊んでいなければ 0 点を出す', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStats(tester, withBonus: true);
    expect(find.text('ベスト 0 点'), findsOneWidget);
  });

  testWidgets('bonus を渡さなければボーナスの欄を出さない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStats(tester, withBonus: false);
    expect(find.text('ボーナスゲーム'), findsNothing);
  });

  testWidgets('既存の難易度別の欄は残っている', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpStats(tester, withBonus: true);
    expect(find.text('やさしい'), findsOneWidget);
    expect(find.text('ふつう'), findsOneWidget);
    expect(find.text('むずかしい'), findsOneWidget);
  });

  group('ホーム画面からの実際の配線', () {
    // 上のテストはすべて StatsScreen を直接組み立てており、
    // HomeScreen._StatsEntry が bonusRepositoryProvider を実際に解決して
    // StatsScreen へ渡す配線そのものは通っていない。ここで実際の
    // ホーム画面から「統計」を開いて確かめる。
    setUp(() {
      // assets/puzzles.json の loadString の Future はプロセス全体で
      // キャッシュされる(app_boot_test.dart 参照)。このグループは
      // HomeScreen を経由するのでこのファイルの他のテストへ影響しない
      // よう evict しておく。
      rootBundle.evict('assets/puzzles.json');
    });

    testWidgets('統計を開くとボーナスの欄も出る', (tester) async {
      SharedPreferences.setMockInitialValues({
        'make10.bonus': jsonEncode({'version': 1, 'bestScore': 720}),
      });
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: HomeScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('統計'));
      await tester.pumpAndSettle();

      expect(find.text('ボーナスゲーム'), findsOneWidget);
      expect(find.text('ベスト 720 点'), findsOneWidget);
    });
  });
}
