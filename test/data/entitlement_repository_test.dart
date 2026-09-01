import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/entitlement_repository.dart';
import 'package:make10/data/models/entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts not entitled', () async {
    final repo = EntitlementRepository();
    await repo.load();
    expect(repo.isEntitled(), isFalse);
    expect(repo.state.source, EntitlementSource.none);
  });

  test('lifetime purchase grants entitlement and never expires', () async {
    final repo = EntitlementRepository();
    await repo.load();
    await repo.grantLifetime();
    expect(repo.isEntitled(), isTrue);
    expect(repo.state.source, EntitlementSource.lifetime);
    expect(repo.state.expiresAt, isNull);
    // Still entitled arbitrarily far in the future.
    expect(repo.isEntitled(now: DateTime(2099, 1, 1)), isTrue);
  });

  test('a fresh monthly grant is entitled immediately', () async {
    final repo = EntitlementRepository();
    await repo.load();
    final now = DateTime(2026, 1, 1);
    await repo.grantMonthly(now: now);
    expect(repo.isEntitled(now: now), isTrue);
    expect(repo.state.source, EntitlementSource.monthly);
  });

  test('a lapsed subscription no longer grants entitlement', () async {
    final repo = EntitlementRepository();
    await repo.load();
    final purchaseTime = DateTime(2026, 1, 1);
    await repo.grantMonthly(now: purchaseTime);
    // Well past the trust window with no reconfirmation from the store.
    final muchLater = purchaseTime.add(const Duration(days: 400));
    expect(repo.isEntitled(now: muchLater), isFalse,
        reason: 'a subscription that was never reconfirmed must lapse');
  });

  test('stays entitled right up to the edge of the trust window', () async {
    final repo = EntitlementRepository();
    await repo.load();
    final purchaseTime = DateTime(2026, 1, 1);
    await repo.grantMonthly(now: purchaseTime);
    final justBefore = purchaseTime.add(kSubscriptionTrustWindow - const Duration(seconds: 1));
    expect(repo.isEntitled(now: justBefore), isTrue);
    final justAfter = purchaseTime.add(kSubscriptionTrustWindow + const Duration(seconds: 1));
    expect(repo.isEntitled(now: justAfter), isFalse);
  });

  test('a renewed subscription extends the trust window from the renewal time', () async {
    final repo = EntitlementRepository();
    await repo.load();
    final purchaseTime = DateTime(2026, 1, 1);
    await repo.grantMonthly(now: purchaseTime);
    final almostLapsed = purchaseTime.add(kSubscriptionTrustWindow - const Duration(days: 1));
    // The store reconfirms the subscription (e.g. a restore at app start).
    await repo.grantMonthly(now: almostLapsed);
    final wouldHaveLapsedUnderTheOldWindow = purchaseTime.add(kSubscriptionTrustWindow + const Duration(days: 1));
    expect(repo.isEntitled(now: wouldHaveLapsedUnderTheOldWindow), isTrue,
        reason: 'the renewal should have pushed the window out further');
  });

  test('a monthly grant never downgrades an existing lifetime purchase', () async {
    final repo = EntitlementRepository();
    await repo.load();
    await repo.grantLifetime();
    await repo.grantMonthly(now: DateTime(2026, 1, 1));
    expect(repo.state.source, EntitlementSource.lifetime);
    expect(repo.state.expiresAt, isNull);
    expect(repo.isEntitled(now: DateTime(2099, 1, 1)), isTrue);
  });

  test('revoke clears entitlement', () async {
    final repo = EntitlementRepository();
    await repo.load();
    await repo.grantLifetime();
    await repo.revoke();
    expect(repo.isEntitled(), isFalse);
    expect(repo.state.source, EntitlementSource.none);
  });

  test('survives a reload (lifetime)', () async {
    final first = EntitlementRepository();
    await first.load();
    await first.grantLifetime();

    final second = EntitlementRepository();
    await second.load();
    expect(second.isEntitled(), isTrue);
    expect(second.state.source, EntitlementSource.lifetime);
  });

  test('survives a reload (monthly, including its expiry)', () async {
    final purchaseTime = DateTime(2026, 1, 1);
    final first = EntitlementRepository();
    await first.load();
    await first.grantMonthly(now: purchaseTime);

    final second = EntitlementRepository();
    await second.load();
    expect(second.isEntitled(now: purchaseTime), isTrue);
    expect(
      second.isEntitled(now: purchaseTime.add(const Duration(days: 400))),
      isFalse,
    );
  });

  test('falls back to not entitled when stored json is corrupt', () async {
    SharedPreferences.setMockInitialValues({'make10.entitlement': '<<broken>>'});
    final repo = EntitlementRepository();
    await repo.load();
    expect(repo.isEntitled(), isFalse);
  });

  test('falls back to not entitled when source has an unrecognized value', () async {
    SharedPreferences.setMockInitialValues({
      'make10.entitlement': jsonEncode({
        'version': 1,
        'source': 'lifetime_but_misspelled',
        'expiresAt': null,
      }),
    });
    final repo = EntitlementRepository();
    await repo.load();
    expect(repo.isEntitled(), isFalse);
  });

  test('falls back to not entitled when source has the wrong type', () async {
    // A lazy cast would let this slip through load() unnoticed. Source must
    // be checked eagerly, not deferred, so the surrounding try/catch in
    // load() actually catches it.
    SharedPreferences.setMockInitialValues({
      'make10.entitlement': jsonEncode({
        'version': 1,
        'source': 1,
        'expiresAt': null,
      }),
    });
    final repo = EntitlementRepository();
    await repo.load();
    expect(repo.isEntitled(), isFalse);
  });

  test('falls back to not entitled when expiresAt is not a valid date string', () async {
    SharedPreferences.setMockInitialValues({
      'make10.entitlement': jsonEncode({
        'version': 1,
        'source': 'monthly',
        'expiresAt': 'not-a-date',
      }),
    });
    final repo = EntitlementRepository();
    await repo.load();
    expect(repo.isEntitled(), isFalse);
  });

  test('falls back to not entitled when the source key is missing entirely', () async {
    SharedPreferences.setMockInitialValues({
      'make10.entitlement': jsonEncode({'version': 1}),
    });
    final repo = EntitlementRepository();
    await repo.load();
    expect(repo.isEntitled(), isFalse);
  });
}
