import 'dart:async';

import 'billing_gateway.dart';

/// Web 版の課金ゲートウェイ。`in_app_purchase` は Android/iOS 専用のため、
/// Web ビルドではこのファイルが選ばれる（`billing_gateway.dart` の
/// conditional import を参照）。このファイルはプラグインを一切 import
/// しない — それが Web ビルドの成果物にプラグインが混入しないことの保証になる。
///
/// 常に「何も買えない・何も権利を与えない」。商品は 1 件も見つからず、
/// 購入は必ず失敗し、エンタイトルメントのストリームには絶対に何も流れない。
class WebBillingGateway implements BillingGateway {
  @override
  Future<void> init() async {}

  @override
  Future<List<BillingProduct>> queryProducts() async => const [];

  @override
  Future<bool> buy(String productId) async => false;

  @override
  Future<void> restorePurchases() async {}

  @override
  Stream<PurchaseUpdate> get purchaseUpdates => const Stream.empty();

  @override
  Stream<String> get entitlementChanges => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

BillingGateway createBillingGateway() => WebBillingGateway();
