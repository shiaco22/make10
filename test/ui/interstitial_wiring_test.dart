// Widget-level tests proving *where* and *when* interstitials actually fire,
// driven through the real Home -> practice / Home -> time attack screens
// with a fake ad gateway swapped in via ProviderScope overrides.
//
// test/domain/ad_policy_test.dart already pins the pure decision logic
// exhaustively. These tests exist because getting that logic right is not
// enough on its own -- the app has to actually consult it at the right
// moment (the 次の問題へ tap, not the クリア! moment; the result screen's
// exit, not its arrival) and never let a missing ad block gameplay. A
// regression here would mean the policy is correct but wired to the wrong
// event, or not wired at all.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/entitlement_repository.dart';
import 'package:make10/game/game_session.dart';
import 'package:make10/game/providers.dart';
import 'package:make10/ui/app.dart';
import 'package:make10/ui/game_screen.dart';
import 'package:make10/ui/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_gateways.dart';
import '../helpers/fixtures.dart';

/// Mirrors app_boot_test.dart's helper of the same purpose: the
/// puzzle/stats/entitlement FutureProviders all show a spinner until they
/// resolve, and the spinner animates forever, so pumpAndSettle can't be used
/// to wait it out.
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

/// Mirrors app_boot_test.dart's helper of the same purpose: once
/// TimeAttackScreen is on screen its Ticker keeps requesting frames every
/// pump until TimeAttackSession.isOver, so pumpAndSettle must never be used
/// to wait out an ordinary navigation transition into it -- it would just
/// keep pumping for the full 120 (virtual) seconds instead of settling.
Future<void> _pumpTransition(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // rootBundle caches loadString's Future per key for the whole process;
    // each test (and, within the restart test, each simulated "run") needs
    // its own fresh load of assets/puzzles.json. See app_boot_test.dart.
    rootBundle.evict('assets/puzzles.json');
  });

  Future<void> bootToHome(
    WidgetTester tester,
    FakeAdGateway ads, {
    EntitlementRepository? entitledAs,
  }) async {
    // Force a full unmount before mounting the new tree. Without this,
    // pumping an identically-shaped ProviderScope(child: Make10App()) again
    // is an *update* to the already-mounted element (same widget type at
    // the same tree position), which preserves the existing
    // ProviderContainer and Navigator stack instead of truly starting over.
    // That matters for "the ad counter survives an app restart" below,
    // which calls bootToHome twice to simulate two separate app runs --
    // without this, the second call would silently keep showing the first
    // run's still-pushed GameScreen instead of a fresh Home screen.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        adGatewayProvider.overrideWithValue(ads),
        if (entitledAs != null)
          entitlementRepositoryProvider.overrideWith((ref) => entitledAs),
      ],
      child: const Make10App(),
    ));
    await _pumpUntilGone(tester, find.byType(CircularProgressIndicator));
  }

  Future<void> startPractice(WidgetTester tester, {String label = 'やさしい'}) async {
    await tester.tap(find.widgetWithText(FilledButton, 'プラクティス'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> startTimeAttack(WidgetTester tester, {String label = 'ふつう'}) async {
    await tester.tap(find.widgetWithText(FilledButton, 'タイムアタック'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    // Not pumpAndSettle: TimeAttackScreen's Ticker starts immediately and
    // would keep it pumping all the way to the 120-second timeout instead
    // of just settling the navigation transition (see _pumpTransition doc).
    await _pumpTransition(tester);
  }

  GameSession currentSession(WidgetTester tester) =>
      tester.widget<GameScreen>(find.byType(GameScreen)).session;

  group('practice: interstitial timing', () {
    testWidgets(
        'not requested before the 3rd clear, and only on the 次の問題へ tap '
        '-- never at the クリア! moment itself', (tester) async {
      final ads = FakeAdGateway(ready: true);
      await bootToHome(tester, ads);
      await startPractice(tester);

      // 1st clear: not due yet.
      playSolution(currentSession(tester));
      await tester.pump();
      expect(find.textContaining('クリア'), findsOneWidget);
      expect(ads.showCount, 0,
          reason: 'must not show right at the クリア! moment');
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();
      expect(ads.showCount, 0, reason: 'not due until the 3rd clear');

      // 2nd clear: still not due.
      playSolution(currentSession(tester));
      await tester.pump();
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();
      expect(ads.showCount, 0, reason: 'only 2 clears since the start');

      // 3rd clear: due, but still not fired at the クリア! moment itself.
      playSolution(currentSession(tester));
      await tester.pump();
      expect(ads.showCount, 0,
          reason: 'the due ad must wait for the 次の問題へ tap, not fire '
              'the instant the board clears');
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();
      expect(ads.showCount, 1,
          reason: 'due exactly on the transition after the 3rd clear');
    });

    testWidgets('gameplay proceeds normally when no ad is loaded',
        (tester) async {
      final ads = FakeAdGateway(ready: false);
      await bootToHome(tester, ads);
      await startPractice(tester);

      for (var i = 0; i < 3; i++) {
        playSolution(currentSession(tester));
        await tester.pump();
        await tester.tap(find.text('次の問題へ'));
        await tester.pumpAndSettle();
      }

      expect(ads.showCount, 0);
      // The 3rd clear's transition ran to completion -- a fresh puzzle is
      // live -- instead of hanging while waiting on an ad that never loaded.
      expect(find.byType(GameScreen), findsOneWidget);
      expect(currentSession(tester).phase, PhaseKind.playing);
      expect(tester.takeException(), isNull);

      // The window must still be considered due (never consumed, since
      // nothing was actually shown) -- confirmed once an ad does load.
      ads.ready = true;
      playSolution(currentSession(tester));
      await tester.pump();
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();
      expect(ads.showCount, 1);
    });
  });

  group('no interstitial ever, when entitled', () {
    testWidgets('practice: never shown despite reaching the 3-clear window',
        (tester) async {
      final ads = FakeAdGateway(ready: true);
      final entitled = EntitlementRepository();
      await entitled.load();
      await entitled.grantLifetime();
      await bootToHome(tester, ads, entitledAs: entitled);
      await startPractice(tester);

      for (var i = 0; i < 4; i++) {
        playSolution(currentSession(tester));
        await tester.pump();
        await tester.tap(find.text('次の問題へ'));
        await tester.pumpAndSettle();
      }

      expect(ads.showCount, 0);
    });

    testWidgets('time attack: never shown even on leaving the result screen',
        (tester) async {
      final ads = FakeAdGateway(ready: true);
      final entitled = EntitlementRepository();
      await entitled.load();
      await entitled.grantLifetime();
      await bootToHome(tester, ads, entitledAs: entitled);
      await startTimeAttack(tester);
      await tester.pumpAndSettle(); // run out the clock

      expect(find.byType(ResultScreen), findsOneWidget);
      await tester.tap(find.text('ホームへ'));
      await tester.pumpAndSettle();

      expect(ads.showCount, 0);
    });
  });

  group('time attack: never during the run', () {
    testWidgets(
        'clearing several puzzles mid-run never requests an interstitial',
        (tester) async {
      final ads = FakeAdGateway(ready: true);
      await bootToHome(tester, ads);
      await startTimeAttack(tester);

      for (var i = 0; i < 3; i++) {
        playSolution(currentSession(tester));
        await tester.pump();
      }

      expect(ads.showCount, 0);
      expect(find.byType(ResultScreen), findsNothing,
          reason: 'still well under 120 seconds of ticks');
    });

    testWidgets(
        'reaching the result screen alone does not show one -- only leaving '
        'it does, after the score was already visible', (tester) async {
      final ads = FakeAdGateway(ready: true);
      await bootToHome(tester, ads);
      await startTimeAttack(tester);

      await tester.pumpAndSettle(); // run out the clock
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.textContaining('スコア'), findsOneWidget,
          reason: 'the score must already be on screen before any ad check');
      expect(ads.showCount, 0,
          reason: 'must not show merely for reaching the result screen');

      await tester.tap(find.text('ホームへ'));
      await tester.pumpAndSettle();

      expect(ads.showCount, 1,
          reason: 'the result screen is the one allowed spot, taken on the '
              'way out, never blocking the score itself');
    });
  });

  group('the ad counter survives an app restart', () {
    testWidgets(
        '2 clears, a simulated restart, then 1 more clear still fires on '
        'schedule', (tester) async {
      // "run 1": two clears, never reaching the 3rd.
      final adsRun1 = FakeAdGateway(ready: true);
      await bootToHome(tester, adsRun1);
      await startPractice(tester);
      playSolution(currentSession(tester));
      await tester.pump();
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();
      playSolution(currentSession(tester));
      await tester.pump();
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();
      expect(adsRun1.showCount, 0);

      // "restart": an entirely new widget tree/ProviderContainer, backed by
      // the same mocked SharedPreferences store -- exactly like a real
      // device's disk surviving a process restart. Note there is no second
      // SharedPreferences.setMockInitialValues call: the point is that the
      // backing store is *not* reset between "run 1" and "run 2".
      rootBundle.evict('assets/puzzles.json');
      final adsRun2 = FakeAdGateway(ready: true);
      await bootToHome(tester, adsRun2);
      await startPractice(tester);

      playSolution(currentSession(tester));
      await tester.pump();
      expect(adsRun2.showCount, 0, reason: 'not at the クリア! moment itself');
      await tester.tap(find.text('次の問題へ'));
      await tester.pumpAndSettle();

      expect(adsRun2.showCount, 1,
          reason: 'the restored count of 2 plus this 1 clear reaches the '
              '3-clear window on the very first clear after restart');
    });
  });
}
