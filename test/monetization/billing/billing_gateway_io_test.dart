import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:make10/monetization/billing/billing_gateway.dart';
// billing_gateway_io.dart also defines its own createBillingGateway()
// (required by the conditional-import pattern -- both branches must expose
// the same name). Hide it here since this file already gets the public
// factory from billing_gateway.dart and only needs IoBillingGateway itself
// from this import.
import 'package:make10/monetization/billing/billing_gateway_io.dart' hide createBillingGateway;
// ProductIds is re-exported by billing_gateway.dart, imported above.

/// in_app_purchase is a federated plugin: every real call funnels through
/// the swappable [InAppPurchasePlatform.instance] singleton. Extending it
/// (rather than implementing it) is the pattern the plugin itself documents
/// for platform implementations, and it doubles as the supported test seam
/// for anything that wraps InAppPurchase.instance -- exactly what
/// [IoBillingGateway] does. This lets these tests drive the real gateway
/// implementation end to end without ever touching a platform channel.
class FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  bool isAvailableResult = true;
  bool buyNonConsumableResult = true;
  final Map<String, ProductDetails> products = {};
  final List<PurchaseParam> buyCalls = [];
  final List<PurchaseDetails> completedPurchases = [];
  int restoreCallCount = 0;
  final _controller = StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => isAvailableResult;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async {
    final found = <ProductDetails>[];
    final notFound = <String>[];
    for (final id in identifiers) {
      final product = products[id];
      if (product == null) {
        notFound.add(id);
      } else {
        found.add(product);
      }
    }
    return ProductDetailsResponse(productDetails: found, notFoundIDs: notFound);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls.add(purchaseParam);
    return buyNonConsumableResult;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completedPurchases.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCallCount++;
  }

  /// Test-only: pushes purchase updates as if they came from the store.
  void emit(List<PurchaseDetails> purchases) => _controller.add(purchases);

  Future<void> close() => _controller.close();
}

ProductDetails _product(String id, {String price = 'JPY 300'}) => ProductDetails(
      id: id,
      title: id,
      description: id,
      price: price,
      rawPrice: 300,
      currencyCode: 'JPY',
    );

PurchaseDetails _purchase(
  String productId,
  PurchaseStatus status, {
  bool pendingCompletePurchase = false,
  String? errorMessage,
}) {
  final details = PurchaseDetails(
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: 'server',
      source: 'test',
    ),
    transactionDate: '0',
    status: status,
  );
  details.pendingCompletePurchase = pendingCompletePurchase;
  if (errorMessage != null) {
    details.error = IAPError(source: 'test', code: 'test_error', message: errorMessage);
  }
  return details;
}

/// Broadcast delivery plus the gateway's own internal awaits (e.g.
/// completePurchase) both cross multiple microtask boundaries. Poll a bounded
/// number of empty delays rather than guessing a single Duration.zero,
/// mirroring test/helpers/fixtures.dart's waitForResultSave.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // InAppPurchase.instance is a memoized singleton whose *first-ever* access
  // in this isolate unconditionally calls registerPlatform() when
  // defaultTargetPlatform is android/iOS/macOS, which overwrites
  // InAppPurchasePlatform.instance with a REAL platform implementation that
  // tries to open a genuine platform channel -- clobbering any fake a test
  // just installed, and failing asynchronously since there is no real
  // channel in this test environment. flutter test's binding reports
  // defaultTargetPlatform as android, so that branch always fires.
  //
  // After that first access, InAppPurchase's own wrapper instance is cached
  // and it never calls registerPlatform() again, so every later access just
  // reads whatever InAppPurchasePlatform.instance currently is. This absorbs
  // that one-time side effect here -- with the detected platform harmlessly
  // overridden to something in_app_purchase does not auto-register for, so
  // neither branch fires -- before any test installs its fake, so each
  // test's own setUp (which runs after this) can safely make its fake stick.
  setUpAll(() {
    final originalOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    try {
      InAppPurchase.instance;
    } finally {
      debugDefaultTargetPlatformOverride = originalOverride;
    }
  });

  late FakeInAppPurchasePlatform fake;
  late IoBillingGateway gateway;

  setUp(() async {
    fake = FakeInAppPurchasePlatform();
    InAppPurchasePlatform.instance = fake;
    gateway = IoBillingGateway();
    await gateway.init();
  });

  tearDown(() async {
    await gateway.dispose();
    await fake.close();
  });

  test('createBillingGateway resolves to a BillingGateway on this (non-web) test run', () {
    // Exercises the conditional-import selector itself: on the VM (which is
    // what flutter test runs on), dart.library.io is available, so this
    // must resolve to the io implementation.
    expect(createBillingGateway(), isA<BillingGateway>());
  });

  test('queryProducts translates found products and ignores unavailable ones', () async {
    fake.products[ProductIds.noAdsLifetime] = _product(ProductIds.noAdsLifetime, price: 'JPY 980');
    final products = await gateway.queryProducts();
    expect(products, hasLength(1));
    expect(products.single.id, ProductIds.noAdsLifetime);
    expect(products.single.formattedPrice, 'JPY 980');
  });

  test('queryProducts returns nothing when the store is unavailable', () async {
    fake.isAvailableResult = false;
    fake.products[ProductIds.noAdsLifetime] = _product(ProductIds.noAdsLifetime);
    expect(await gateway.queryProducts(), isEmpty);
  });

  test('buy fails without calling the platform when the product was never queried', () async {
    final started = await gateway.buy(ProductIds.noAdsLifetime);
    expect(started, isFalse);
    expect(fake.buyCalls, isEmpty);
  });

  test('buy forwards a queried product to buyNonConsumable', () async {
    fake.products[ProductIds.noAdsLifetime] = _product(ProductIds.noAdsLifetime);
    await gateway.queryProducts();
    final started = await gateway.buy(ProductIds.noAdsLifetime);
    expect(started, isTrue);
    expect(fake.buyCalls, hasLength(1));
    expect(fake.buyCalls.single.productDetails.id, ProductIds.noAdsLifetime);
  });

  test('buy reports failure when the platform rejects the request', () async {
    fake.products[ProductIds.noAdsLifetime] = _product(ProductIds.noAdsLifetime);
    await gateway.queryProducts();
    fake.buyNonConsumableResult = false;
    expect(await gateway.buy(ProductIds.noAdsLifetime), isFalse);
  });

  test('a pending purchase is reported but grants nothing yet', () async {
    final updates = <PurchaseUpdate>[];
    final grants = <String>[];
    gateway.purchaseUpdates.listen(updates.add);
    gateway.entitlementChanges.listen(grants.add);

    fake.emit([_purchase(ProductIds.noAdsMonthly, PurchaseStatus.pending)]);
    await flushMicrotasks();

    expect(updates, hasLength(1));
    expect(updates.single.outcome, PurchaseOutcome.pending);
    expect(grants, isEmpty);
    expect(fake.completedPurchases, isEmpty,
        reason: 'completing a pending purchase throws per the plugin docs');
  });

  test('a purchased (new) purchase grants entitlement and gets completed', () async {
    final updates = <PurchaseUpdate>[];
    final grants = <String>[];
    gateway.purchaseUpdates.listen(updates.add);
    gateway.entitlementChanges.listen(grants.add);

    fake.emit([
      _purchase(ProductIds.noAdsLifetime, PurchaseStatus.purchased, pendingCompletePurchase: true),
    ]);
    await flushMicrotasks();

    expect(updates.single.outcome, PurchaseOutcome.granted);
    expect(updates.single.isRestore, isFalse);
    expect(grants, [ProductIds.noAdsLifetime]);
    expect(fake.completedPurchases, hasLength(1));
  });

  test('a restored purchase grants entitlement and is flagged as a restore', () async {
    final updates = <PurchaseUpdate>[];
    final grants = <String>[];
    gateway.purchaseUpdates.listen(updates.add);
    gateway.entitlementChanges.listen(grants.add);

    fake.emit([
      _purchase(ProductIds.noAdsMonthly, PurchaseStatus.restored, pendingCompletePurchase: true),
    ]);
    await flushMicrotasks();

    expect(updates.single.outcome, PurchaseOutcome.granted);
    expect(updates.single.isRestore, isTrue);
    expect(grants, [ProductIds.noAdsMonthly]);
    expect(fake.completedPurchases, hasLength(1));
  });

  test('a canceled purchase is reported but grants nothing and is not completed', () async {
    final updates = <PurchaseUpdate>[];
    final grants = <String>[];
    gateway.purchaseUpdates.listen(updates.add);
    gateway.entitlementChanges.listen(grants.add);

    fake.emit([_purchase(ProductIds.noAdsMonthly, PurchaseStatus.canceled)]);
    await flushMicrotasks();

    expect(updates.single.outcome, PurchaseOutcome.canceled);
    expect(grants, isEmpty);
    expect(fake.completedPurchases, isEmpty);
  });

  test('an error purchase is reported with its message and does not grant entitlement', () async {
    final updates = <PurchaseUpdate>[];
    final grants = <String>[];
    gateway.purchaseUpdates.listen(updates.add);
    gateway.entitlementChanges.listen(grants.add);

    fake.emit([
      _purchase(
        ProductIds.noAdsMonthly,
        PurchaseStatus.error,
        pendingCompletePurchase: true,
        errorMessage: 'card declined',
      ),
    ]);
    await flushMicrotasks();

    expect(updates.single.outcome, PurchaseOutcome.failed);
    expect(updates.single.errorMessage, 'card declined');
    expect(grants, isEmpty);
    expect(fake.completedPurchases, hasLength(1),
        reason: 'an unacknowledged error purchase still needs completing');
  });

  test('restorePurchases delegates to the platform', () async {
    await gateway.restorePurchases();
    expect(fake.restoreCallCount, 1);
  });

  test('entitlementChanges ignores a granted purchase for an unrecognized product id', () async {
    final grants = <String>[];
    gateway.entitlementChanges.listen(grants.add);

    fake.emit([_purchase('some_other_product', PurchaseStatus.purchased)]);
    await flushMicrotasks();

    expect(grants, isEmpty);
  });
}
