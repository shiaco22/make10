import 'package:flutter_test/flutter_test.dart';
import 'package:make10/monetization/billing/billing_gateway_web.dart';

void main() {
  group('WebBillingGateway is completely inert', () {
    test('queries return no products', () async {
      final gateway = WebBillingGateway();
      expect(await gateway.queryProducts(), isEmpty);
    });

    test('buying anything fails without throwing', () async {
      final gateway = WebBillingGateway();
      expect(await gateway.buy('make10_noads_lifetime'), isFalse);
      expect(await gateway.buy('make10_noads_monthly'), isFalse);
      expect(await gateway.buy('anything'), isFalse);
    });

    test('restorePurchases is a no-op', () async {
      final gateway = WebBillingGateway();
      await gateway.restorePurchases(); // must not throw
    });

    test('purchaseUpdates never emits', () async {
      final gateway = WebBillingGateway();
      final events = <Object?>[];
      final sub = gateway.purchaseUpdates.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });

    test('entitlementChanges never emits', () async {
      final gateway = WebBillingGateway();
      final events = <Object?>[];
      final sub = gateway.entitlementChanges.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });

    test('init and dispose do not throw', () async {
      final gateway = WebBillingGateway();
      await gateway.init();
      await gateway.dispose();
    });
  });
}
