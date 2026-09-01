import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_gateway.dart';

/// Android/iOS 版の課金ゲートウェイ。`in_app_purchase` を薄くラップする。
///
/// ## テストでの差し替え方
///
/// `in_app_purchase` はフェデレーテッド・プラグインで、実体は
/// `InAppPurchasePlatform.instance`（`plugin_platform_interface` の
/// `PlatformInterface` を継承した差し替え可能なシングルトン）に対する
/// 呼び出しに委譲されている。テストは、[InAppPurchasePlatform] を
/// `extends` した偽実装を作り、使う前に
/// `InAppPurchasePlatform.instance = FakeInAppPurchasePlatform()` を
/// 代入すればよい — 詳しくは `test/monetization/billing/billing_gateway_io_test.dart`
/// を参照。このクラス自身はコンストラクタで何も受け取らない
/// （`InAppPurchase.instance` は元々このシングルトン経由でしか実体を
/// 持てないため、コンストラクタ注入は意味を成さない）。
class IoBillingGateway implements BillingGateway {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final Map<String, ProductDetails> _productCache = {};
  final StreamController<PurchaseUpdate> _updatesController =
      StreamController<PurchaseUpdate>.broadcast();
  final StreamController<String> _entitlementController =
      StreamController<String>.broadcast();

  @override
  Future<void> init() async {
    // 起動後なるべく早く購読を始める（プラグインの推奨）。取りこぼした
    // 更新は、次回起動時に再配信されるものに限られる。
    await _subscription?.cancel();
    _subscription = _iap.purchaseStream.listen(_onPurchaseUpdates);
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      _emit(purchase);
      // purchased / restored / error はすべて completePurchase が必要
      // （見送ると iOS は再配信を繰り返し、Android は 3 日後に自動返金する）。
      // pendingCompletePurchase がプラットフォーム側の判断そのもの。
      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (_) {
          // 失敗しても致命的ではない — 未完了のまま残るだけで、次回
          // 起動時に purchaseStream へ再配信されるため、そこで再試行できる。
        }
      }
    }
  }

  void _emit(PurchaseDetails purchase) {
    final PurchaseOutcome outcome = switch (purchase.status) {
      PurchaseStatus.pending => PurchaseOutcome.pending,
      PurchaseStatus.purchased => PurchaseOutcome.granted,
      PurchaseStatus.restored => PurchaseOutcome.granted,
      PurchaseStatus.canceled => PurchaseOutcome.canceled,
      PurchaseStatus.error => PurchaseOutcome.failed,
    };
    _updatesController.add(
      PurchaseUpdate(
        productId: purchase.productID,
        outcome: outcome,
        isRestore: purchase.status == PurchaseStatus.restored,
        errorMessage: purchase.error?.message,
      ),
    );
    if (outcome == PurchaseOutcome.granted &&
        ProductIds.all.contains(purchase.productID)) {
      _entitlementController.add(purchase.productID);
    }
  }

  @override
  Future<List<BillingProduct>> queryProducts() async {
    if (!await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails(ProductIds.all);
    _productCache
      ..clear()
      ..addEntries(
        response.productDetails.map((details) => MapEntry(details.id, details)),
      );
    return [
      for (final details in response.productDetails)
        BillingProduct(
          id: details.id,
          title: details.title,
          formattedPrice: details.price,
        ),
    ];
  }

  @override
  Future<bool> buy(String productId) async {
    // queryProducts() で得た ProductDetails が無ければ購入フローを
    // 開始しない — ストアの商品情報なしに buyNonConsumable を呼んでも
    // 成功しないし、未知の文字列を渡す経路をそもそも作らない。
    final details = _productCache[productId];
    if (details == null) return false;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Stream<PurchaseUpdate> get purchaseUpdates => _updatesController.stream;

  @override
  Stream<String> get entitlementChanges => _entitlementController.stream;

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _updatesController.close();
    await _entitlementController.close();
  }
}

BillingGateway createBillingGateway() => IoBillingGateway();
