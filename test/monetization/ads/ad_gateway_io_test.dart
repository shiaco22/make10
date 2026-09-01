import 'package:flutter_test/flutter_test.dart';
import 'package:make10/monetization/ads/ad_gateway.dart';
// ad_gateway_io.dart also defines its own createAdGateway() (required by the
// conditional-import pattern -- both branches must expose the same name).
// Hide it here since this file already gets the public factory from
// ad_gateway.dart and only needs IoAdGateway itself from this import.
import 'package:make10/monetization/ads/ad_gateway_io.dart' hide createAdGateway;

/// google_mobile_ads talks to the platform through raw method channels, not
/// through a swappable platform-interface singleton like in_app_purchase
/// does, so there is no officially supported seam to fake `InterstitialAd`
/// itself in a plain unit test. Actually loading or showing an ad here would
/// throw a MissingPluginException.
///
/// What these tests CAN verify without touching a channel: importing this
/// file forces the whole implementation to compile (this is the closest
/// thing to `flutter analyze` this repository can run -- see the task's
/// notes on the non-ASCII checkout path), and the getters/no-ad-loaded paths
/// that never reach into the plugin behave exactly like the contract
/// promises: never ready by default, and dispose/showIfAvailable are safe
/// no-ops when nothing is loaded.
void main() {
  test('createAdGateway resolves to an AdGateway on this (non-web) test run', () {
    // Exercises the conditional-import selector itself: on the VM (which is
    // what flutter test runs on), dart.library.io is available, so this
    // must resolve to the io implementation.
    expect(createAdGateway(), isA<AdGateway>());
  });

  test('starts with no ad ready', () {
    final gateway = IoAdGateway();
    expect(gateway.isAdReady, isFalse);
  });

  test('showIfAvailable with nothing loaded returns immediately without touching the plugin', () async {
    final gateway = IoAdGateway();
    await gateway.showIfAvailable();
    expect(gateway.isAdReady, isFalse);
  });

  test('dispose with nothing loaded does not throw', () async {
    final gateway = IoAdGateway();
    await gateway.dispose();
  });
}
