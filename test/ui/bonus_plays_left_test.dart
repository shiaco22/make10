import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

String today() => bonusDateKey(DateTime.now());

List<int> playableCells() => const [
      1, 1, 3, 1, 2, //
      3, 1, 2, 3, 1, //
      2, 3, 1, 2, 3, //
      1, 2, 3, 1, 2, //
      3, 1, 2, 3, 1, //
    ];

void setBonus({
  int bestScore = 0,
  String? day,
  int earned = 0,
  int played = 0,
  bool inProgress = false,
}) {
  SharedPreferences.setMockInitialValues({
    'make10.bonus': jsonEncode({
      'version': 2,
      'bestScore': bestScore,
      'day': day,
      'earned': earned,
      'played': played,
      if (inProgress)
        'inProgress': {'grid': playableCells(), 'score': 0, 'repairsUsed': 0},
    }),
  });
}

Future<void> pumpHome(WidgetTester tester) async {
  // 問題データを読み直させる。これを忘れると 2 つ目以降のテストで
  // pumpAndSettle が返らない（app_boot_test.dart に同じ注記がある）。
  rootBundle.evict('assets/puzzles.json');
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: HomeScreen())),
  );
  await tester.pumpAndSettle();
}

TextButton bonusButton(WidgetTester tester) => tester.widget<TextButton>(
      find.ancestor(
        of: find.textContaining('ボーナスゲーム'),
        matching: find.byType(TextButton),
      ),
    );

void main() {
  testWidgets('残り 3 回なら「あと 3 回」と出て押せる', (tester) async {
    setBonus(day: today(), earned: 3, played: 0);
    await pumpHome(tester);
    expect(find.text('★ ボーナスゲーム（あと 3 回）'), findsOneWidget);
    expect(bonusButton(tester).onPressed, isNotNull);
  });

  testWidgets('残り 1 回なら「あと 1 回」', (tester) async {
    setBonus(day: today(), earned: 3, played: 2);
    await pumpHome(tester);
    expect(find.text('★ ボーナスゲーム（あと 1 回）'), findsOneWidget);
  });

  testWidgets('残り 0・上限未満なら条件を出して押せない', (tester) async {
    setBonus(day: today(), earned: 2, played: 2);
    await pumpHome(tester);
    expect(
      find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
      findsOneWidget,
    );
    expect(bonusButton(tester).onPressed, isNull);
  });

  testWidgets('未獲得も同じ文言', (tester) async {
    // やるべきことが同じなので区別しない（仕様 §4）。
    setBonus();
    await pumpHome(tester);
    expect(
      find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
      findsOneWidget,
    );
    expect(bonusButton(tester).onPressed, isNull);
  });

  testWidgets('5 回使い切ったら「また明日」とベスト', (tester) async {
    setBonus(
      bestScore: 859,
      day: today(),
      earned: kBonusPlaysPerDay,
      played: kBonusPlaysPerDay,
    );
    await pumpHome(tester);
    expect(find.text('ボーナスゲーム（また明日） ベスト 859'), findsOneWidget);
    expect(bonusButton(tester).onPressed, isNull);
  });

  testWidgets('中断があれば残り回数より優先される', (tester) async {
    setBonus(day: today(), earned: 4, played: 1, inProgress: true);
    await pumpHome(tester);
    expect(find.text('ボーナスゲーム（続きから）'), findsOneWidget);
    expect(bonusButton(tester).onPressed, isNotNull);
  });

  testWidgets('前日の残りは翌日に持ち越されない', (tester) async {
    final y = bonusDateKey(DateTime.now().subtract(const Duration(days: 1)));
    setBonus(day: y, earned: 5, played: 0);
    await pumpHome(tester);
    expect(
      find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
      findsOneWidget,
    );
  });

  testWidgets('既存の 3 つの入口は残っている', (tester) async {
    setBonus();
    await pumpHome(tester);
    expect(find.text('プラクティス'), findsOneWidget);
    expect(find.text('タイムアタック'), findsOneWidget);
    expect(find.text('統計'), findsOneWidget);
  });
}
