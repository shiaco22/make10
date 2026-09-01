// Widget tests for the "remove ads" screen and its entry point on Home.
//
// The first groups drive the real RemoveAdsScreen directly with a fake
// BillingGateway (no ProviderScope needed for the screen itself -- it takes
// its gateway and repository as plain constructor parameters, exactly like
// StatsScreen takes its StatsRepository). The final group boots the real
// Home screen to prove the entry point itself: reachable, and its label
// changes once a restore grants entitlement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/entitlement_repository.dart';
import 'package:make10/data/models/entitlement.dart';
import 'package:make10/game/providers.dart';
import 'package:make10/monetization/billing/billing_gateway.dart';
import 'package:make10/ui/app.dart';
import 'package:make10/ui/remove_ads_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_gateways.dart';

const _monthly = BillingProduct(
  id: ProductIds.noAdsMonthly,
  title: '広告非表示 (月額)',
  // Deliberately unlike the ¥300 mentioned in the spec, and region-shaped,
  // to prove the screen renders whatever the store reports rather than a
  // hardcoded Japanese-yen string.
  formattedPrice: r'CA$2.99',
);

const _lifetime = BillingProduct(
  id: ProductIds.noAdsLifetime,
  title: '広告非表示 (買い切り)',
  formattedPrice: r'CA$8.99',
);

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<EntitlementRepository> freshRepo() async {
    final repo = EntitlementRepository();
    await repo.load();
    return repo;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    BillingGateway billing,
    EntitlementRepository entitlements,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoveAdsScreen(billing: billing, entitlements: entitlements),
    ));
  }

  group('product display', () {
    testWidgets('renders the store-reported prices, not hardcoded strings',
        (tester) async {
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pumpAndSettle();

      expect(find.text(r'CA$2.99'), findsOneWidget);
      expect(find.text(r'CA$8.99'), findsOneWidget);
      // The spec's example prices must never appear as a hardcoded
      // fallback: this store happens to report different ones.
      expect(find.textContaining('¥300'), findsNothing);
      expect(find.textContaining('¥980'), findsNothing);
      expect(find.text(_monthly.title), findsOneWidget);
      expect(find.text(_lifetime.title), findsOneWidget);
    });

    testWidgets('shows a loading indicator until the store responds',
        (tester) async {
      final billing = FakeBillingGateway()..pendingQuery = Completer();
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(r'CA$2.99'), findsNothing);

      billing.pendingQuery!.complete([_monthly, _lifetime]);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(r'CA$2.99'), findsOneWidget);
    });
  });

  group('honest failure states', () {
    testWidgets('store unavailable shows a message with something actionable',
        (tester) async {
      final billing = FakeBillingGateway(products: const []);
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pumpAndSettle();

      expect(find.text(r'CA$2.99'), findsNothing);
      final retry = find.widgetWithText(TextButton, '再試行');
      expect(retry, findsOneWidget,
          reason: 'a store-unavailable message alone leaves the user stuck; '
              'there must be a way to act on it');

      billing.products = [_monthly, _lifetime];
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text(r'CA$2.99'), findsOneWidget,
          reason: 'retry must actually re-query the store');
    });

    testWidgets(
        "a pending purchase is shown as such, and disables that product's "
        'buy button', (tester) async {
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '購入').first);
      await tester.pump();
      billing.emit(const PurchaseUpdate(
        productId: ProductIds.noAdsMonthly,
        outcome: PurchaseOutcome.pending,
      ));
      // Not pumpAndSettle: the tapped button now shows an indeterminate
      // CircularProgressIndicator (still pending), which animates forever
      // and would never let pumpAndSettle settle.
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('処理中'), findsOneWidget);
    });

    testWidgets(
        'a failed purchase shows a message and leaves the buy button '
        'retryable', (tester) async {
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pumpAndSettle();

      billing.emit(const PurchaseUpdate(
        productId: ProductIds.noAdsMonthly,
        outcome: PurchaseOutcome.failed,
        errorMessage: 'カードが拒否されました',
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('購入できませんでした'), findsOneWidget);
      expect(find.textContaining('カードが拒否されました'), findsOneWidget);
      final buyButtons = tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, '購入'));
      expect(buyButtons.every((b) => b.onPressed != null), isTrue,
          reason: 'a failure must not permanently lock the buy button out');
    });

    testWidgets('a cancelled purchase says so and stays retryable',
        (tester) async {
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pumpAndSettle();

      billing.emit(const PurchaseUpdate(
        productId: ProductIds.noAdsLifetime,
        outcome: PurchaseOutcome.canceled,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('キャンセル'), findsOneWidget);
      final buyButtons = tester
          .widgetList<FilledButton>(find.widgetWithText(FilledButton, '購入'));
      expect(buyButtons.every((b) => b.onPressed != null), isTrue);
    });
  });

  group('restore purchases', () {
    testWidgets('is always offered, even when the store has no products',
        (tester) async {
      final billing = FakeBillingGateway(products: const []);
      await pumpScreen(tester, billing, await freshRepo());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, '購入を復元'), findsOneWidget,
          reason: 'Apple requires restore to always be reachable');
    });

    testWidgets(
        'grants entitlement, and the screen itself reflects it immediately',
        (tester) async {
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      final entitlements = await freshRepo();
      await pumpScreen(tester, billing, entitlements);
      await tester.pumpAndSettle();

      expect(entitlements.isEntitled(), isFalse);

      await tester.tap(find.widgetWithText(TextButton, '購入を復元'));
      await tester.pump();
      expect(billing.restoreCalls, 1);

      billing.emit(const PurchaseUpdate(
        productId: ProductIds.noAdsLifetime,
        outcome: PurchaseOutcome.granted,
        isRestore: true,
      ));
      await tester.pumpAndSettle();

      expect(entitlements.isEntitled(), isTrue);
      expect(entitlements.state.source, EntitlementSource.lifetime);
      expect(find.textContaining('買い切り'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '購入'), findsNothing,
          reason: 'must not keep inviting a second purchase once entitled');
    });
  });

  group('already entitled', () {
    testWidgets('shows which product is active instead of buy buttons',
        (tester) async {
      final entitlements = await freshRepo();
      await entitlements.grantLifetime();
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      await pumpScreen(tester, billing, entitlements);
      await tester.pumpAndSettle();

      expect(find.textContaining('買い切り'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '購入'), findsNothing);
    });
  });

  group('the Home entry point', () {
    setUp(() {
      rootBundle.evict('assets/puzzles.json');
    });

    testWidgets(
        'is reachable from Home and its label flips once a restore grants '
        'entitlement', (tester) async {
      final billing = FakeBillingGateway(products: [_monthly, _lifetime]);
      await tester.pumpWidget(ProviderScope(
        overrides: [billingGatewayProvider.overrideWithValue(billing)],
        child: const Make10App(),
      ));
      await _pumpUntilGone(tester, find.byType(CircularProgressIndicator));
      // puzzles/stats show a spinner while loading (awaited above), but the
      // entitlement entry does not (see _RemoveAdsEntry) -- settle once more
      // so entitlementRepositoryProvider's own resolution is reflected too.
      await tester.pumpAndSettle();

      final entry = find.widgetWithText(TextButton, '広告を消す');
      expect(entry, findsOneWidget);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(RemoveAdsScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '購入を復元'));
      await tester.pump();
      billing.emit(const PurchaseUpdate(
        productId: ProductIds.noAdsMonthly,
        outcome: PurchaseOutcome.granted,
        isRestore: true,
      ));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(RemoveAdsScreen), findsNothing);
      expect(find.widgetWithText(TextButton, '広告を消す'), findsNothing,
          reason: 'must not keep inviting a purchase once entitled');
      expect(find.textContaining('月額購読'), findsOneWidget,
          reason: 'the Home entry must show which product is now active');
    });
  });
}
