// 本番の起動経路（main.dart が組み立てるのと同じ ProviderScope + Make10App）
// を通しで動かすスモークテスト。
//
// 既存のテストは軒並み test/helpers/fixtures.dart 経由で dart:io の
// File(...) からパズルデータを読んでおり、PuzzleRepository.loadFromAsset()
// （rootBundle 経由）も pubspec.yaml の assets 宣言も一度も通っていなかった。
// puzzleRepositoryProvider をここで上書きしないのはそれが理由で、
// assets/puzzles.json へのパスが 1 文字でも間違っていれば、この
// テストは（フィクスチャ側は素通りしたまま）ここで失敗するはずである。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/ui/app.dart';
import 'package:make10/ui/game_screen.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:make10/ui/result_screen.dart';
import 'package:make10/ui/time_attack_screen.dart';
import 'package:make10/ui/widgets/card_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [CircularProgressIndicator] が消えるまでポンプし続ける。
///
/// puzzleRepositoryProvider / statsRepositoryProvider はどちらも
/// FutureProvider で、解決までローディングスピナーを出す。スピナーは
/// 常時アニメーションしているので pumpAndSettle は使えない（一生終わらない）。
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 40,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('pumpUntilGone: still present after $maxTries tries');
}

/// MaterialPageRoute の画面遷移が終わるのに十分な、有限の仮想時間だけ進める。
///
/// TimeAttackScreen が積んだ Ticker は isOver になるまでフレームを出し
/// 続けるため、それが動いている間・動き出す直前後は pumpAndSettle を
/// 使わない（自然に時間切れまで進んでしまいかねない）。遷移待ちはこちらで
/// 有限回に区切る。
Future<void> pumpTransition(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // rootBundle is a process-wide singleton that caches loadString's
    // Future per key across every test in this file. Awaiting that cached
    // Future from a later test's own fake-async zone never resolves, so
    // each test needs its own fresh load of the same real asset key.
    rootBundle.evict('assets/puzzles.json');
  });

  Future<void> bootToHome(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: Make10App()));
    await pumpUntilGone(tester, find.byType(CircularProgressIndicator));
  }

  testWidgets('cold boot reaches the title screen', (tester) async {
    await bootToHome(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('MAKE 10'), findsOneWidget);
    expect(find.text('プラクティス'), findsOneWidget);
    expect(find.text('タイムアタック'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the app supplies both a light and a dark theme from the '
      'same seed color', (tester) async {
    await bootToHome(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme, isNotNull);
    expect(app.darkTheme, isNotNull);
    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
    // ColorScheme.fromSeed is a pure function of its inputs, so an exact
    // match here pins both themes to the same seed color (Colors.indigo)
    // -- not just "some" light/dark theme each.
    expect(
      app.theme!.colorScheme,
      ColorScheme.fromSeed(seedColor: Colors.indigo),
    );
    expect(
      app.darkTheme!.colorScheme,
      ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    );
    // themeMode is left at its default (system) so the OS setting decides.
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets(
      'home -> practice -> やさしい reaches a board of four cards loaded '
      'through the real asset bundle', (tester) async {
    await bootToHome(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'プラクティス'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('やさしい'));
    await tester.pumpAndSettle();

    // 4 枚の CardTile が描画されるのは、PuzzleRepository.loadFromAsset()
    // が rootBundle 経由で assets/puzzles.json を実際に読み、4 難易度の
    // プールを構築できたことの直接証拠になる。
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(CardTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'practice shows a puzzle counter that starts at 1 and advances when a '
      'new puzzle is dealt', (tester) async {
    await bootToHome(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'プラクティス'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('やさしい'));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('問題 1'), findsOneWidget);

    await tester.tap(find.text('スキップ'));
    await tester.pump();

    expect(find.text('問題 2'), findsOneWidget);
    expect(find.text('問題 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'home -> time attack -> difficulty -> time-up -> もう一度 completes '
      'without exception', (tester) async {
    await bootToHome(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'タイムアタック'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ふつう'));
    await pumpTransition(tester);

    expect(find.byType(TimeAttackScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsOneWidget,
        reason: 'should still be live, not yet timed out');
    expect(tester.takeException(), isNull);

    // Ticker は TimeAttackSession.isOver になるまでフレームを出し続ける
    // ので、pumpAndSettle が自然に 120 秒分の時間切れまで到達する。
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.text('もう一度'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('もう一度'));
    // 同じタップの中で、古いセッションの pop（dispose を予約）と
    // 新しいセッション・新しい Ticker の push が両方起きる。
    await pumpTransition(tester);

    // ちょうど 1 つの TimeAttackScreen が残っている（pop 漏れで 0 でも、
    // 古い画面が残って 2 つでもない）こと、新しいセッションで盤面が
    // 再び生きていることを確認する -- これが「dispose-and-recreate の
    // 配線」が壊れていないことの証拠になる。
    expect(find.byType(TimeAttackScreen), findsOneWidget);
    expect(find.byType(ResultScreen), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('time attack does not show a puzzle counter', (tester) async {
    await bootToHome(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'タイムアタック'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ふつう'));
    await pumpTransition(tester);

    expect(find.byType(TimeAttackScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsOneWidget);
    // GameSession.puzzleNumber exists in both modes, but only practice's
    // statusRow (built in HomeScreen) renders it; time attack's statusRow
    // is the clock + score row built by TimeAttackScreen itself.
    expect(find.textContaining('問題'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
