import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/entitlement_repository.dart';
import 'package:make10/domain/ad_policy.dart';
import 'package:make10/game/interstitial_ad_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_gateways.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<InterstitialAdCoordinator> buildCoordinator({
    required FakeAdGateway gateway,
    int initialClearsSinceLastAd = 0,
    bool entitled = false,
  }) async {
    final entitlements = EntitlementRepository();
    await entitlements.load();
    if (entitled) await entitlements.grantLifetime();
    return InterstitialAdCoordinator(
      policy: AdPolicy(initialClearsSinceLastAd: initialClearsSinceLastAd),
      gateway: gateway,
      entitlements: entitlements,
      persistClearsSinceLastAd: (_) async {},
    );
  }

  group('onPracticeClearAdvance', () {
    test('does not show before the 3rd clear', () async {
      final gateway = FakeAdGateway(ready: true);
      final coordinator = await buildCoordinator(gateway: gateway);

      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();

      expect(gateway.showCount, 0);
    });

    test('shows exactly on the 3rd clear and resets the policy counter',
        () async {
      final gateway = FakeAdGateway(ready: true);
      final coordinator = await buildCoordinator(gateway: gateway);

      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();

      expect(gateway.showCount, 1);
      expect(coordinator.policy.clearsSinceLastAd, 0,
          reason: 'a successful show must restart the 3-clear window');
    });

    test('persists the updated counter after every clear', () async {
      final gateway = FakeAdGateway(ready: true);
      final saved = <int>[];
      final entitlements = EntitlementRepository();
      await entitlements.load();
      final coordinator = InterstitialAdCoordinator(
        policy: AdPolicy(),
        gateway: gateway,
        entitlements: entitlements,
        persistClearsSinceLastAd: (value) async {
          saved.add(value);
        },
      );

      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();

      expect(saved, [1, 2, 0]);
    });

    test('does not consume the counter when no ad is loaded', () async {
      final gateway = FakeAdGateway(ready: false);
      final coordinator = await buildCoordinator(gateway: gateway);

      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();
      await coordinator.onPracticeClearAdvance();

      expect(gateway.showCount, 0);
      expect(coordinator.policy.clearsSinceLastAd, 3,
          reason: 'must stay due so the very next loaded ad still fires');
    });

    test('never shows when entitled, no matter how many clears', () async {
      final gateway = FakeAdGateway(ready: true);
      final coordinator =
          await buildCoordinator(gateway: gateway, entitled: true);

      for (var i = 0; i < 5; i++) {
        await coordinator.onPracticeClearAdvance();
      }

      expect(gateway.showCount, 0);
    });

    test('restoring a counter saved from a previous run fires on the very '
        'next clear', () async {
      final gateway = FakeAdGateway(ready: true);
      final coordinator = await buildCoordinator(
        gateway: gateway,
        initialClearsSinceLastAd: 2,
      );

      await coordinator.onPracticeClearAdvance();

      expect(gateway.showCount, 1);
    });
  });

  group('onLeavingTimeAttackResult', () {
    test('shows regardless of the (unrelated) practice clear counter',
        () async {
      final gateway = FakeAdGateway(ready: true);
      final coordinator = await buildCoordinator(gateway: gateway);

      await coordinator.onLeavingTimeAttackResult();

      expect(gateway.showCount, 1);
    });

    test('never shows when entitled', () async {
      final gateway = FakeAdGateway(ready: true);
      final coordinator =
          await buildCoordinator(gateway: gateway, entitled: true);

      await coordinator.onLeavingTimeAttackResult();

      expect(gateway.showCount, 0);
    });

    test('does nothing when no ad is loaded', () async {
      final gateway = FakeAdGateway(ready: false);
      final coordinator = await buildCoordinator(gateway: gateway);

      await coordinator.onLeavingTimeAttackResult();

      expect(gateway.showCount, 0);
    });
  });
}
