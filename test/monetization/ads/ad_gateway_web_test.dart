import 'package:flutter_test/flutter_test.dart';
import 'package:make10/monetization/ads/ad_gateway_web.dart';

void main() {
  group('WebAdGateway is completely inert', () {
    test('never has an ad ready', () {
      final gateway = WebAdGateway();
      expect(gateway.isAdReady, isFalse);
    });

    test('showIfAvailable returns immediately without blocking gameplay', () async {
      final gateway = WebAdGateway();
      // If this ever hung, the test itself would time out -- that is the
      // "must never block" contract being enforced.
      await gateway.showIfAvailable();
      expect(gateway.isAdReady, isFalse);
    });

    test('init, preload and dispose all complete without doing anything', () async {
      final gateway = WebAdGateway();
      await gateway.init();
      await gateway.preload();
      expect(gateway.isAdReady, isFalse);
      await gateway.dispose();
    });
  });
}
