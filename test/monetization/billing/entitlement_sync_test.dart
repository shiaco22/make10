// Startup wiring between the billing gateway and the entitlement record.
//
// The bug this guards: a monthly subscription renews on Google Play without
// the app hearing about it, and the app only trusts a monthly entitlement
// for 35 days after it last confirmed it. Without a sync at startup, a
// subscriber who keeps paying gets ads back on day 36.
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/entitlement_repository.dart';
import 'package:make10/monetization/billing/billing_gateway.dart';
import 'package:make10/monetization/billing/entitlement_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_gateways.dart';

/// Broadcast delivery and the repository's own awaits cross several
/// microtask boundaries; drain them rather than guessing a single tick.
Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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

  test(
      'a subscriber who keeps paying stays ad-free past the 35-day window '
      'once the startup sync sees the subscription', () async {
    final entitlements = await freshRepo();
    final purchasedAt = DateTime.now().subtract(const Duration(days: 30));
    await entitlements.grantMonthly(now: purchasedAt);
    final day36 = purchasedAt.add(const Duration(days: 36));
    expect(entitlements.isEntitled(now: day36), isFalse,
        reason: 'precondition: without a sync, day 36 is past the window');

    final billing = FakeBillingGateway()
      ..syncResults = const [
        PurchaseUpdate(
          productId: ProductIds.noAdsMonthly,
          outcome: PurchaseOutcome.granted,
          isRestore: true,
        ),
      ];
    final subscription =
        startEntitlementSync(billing: billing, entitlements: entitlements);
    await _flush();

    expect(entitlements.isEntitled(now: day36), isTrue);
    await subscription.cancel();
  });

  test('a startup sync that fails does not escape to the caller', () async {
    final billing = FakeBillingGateway()
      ..syncError = StateError('Play Store unreachable');
    final subscription =
        startEntitlementSync(billing: billing, entitlements: await freshRepo());
    await _flush();

    // Reaching this line without an uncaught async error is the point; the
    // count proves the sync was actually attempted.
    expect(billing.syncCalls, 1);
    await subscription.cancel();
  });
}
