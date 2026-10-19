import 'dart:async';

import 'package:make10/monetization/ads/ad_gateway.dart';
import 'package:make10/monetization/billing/billing_gateway.dart';

/// テスト用の [AdGateway] 偽実装。
///
/// 実際のプラグイン (`google_mobile_ads`) には一切触れない。[ready] を
/// テストが直接読み書きすることで「読み込み済み / 未読み込み」を自由に
/// 制御できる。[showIfAvailable] は実物と同じ契約を再現する: 表示できたら
/// [showCount] を増やし、実物の `IoAdGateway` 同様その広告を「消費」して
/// [ready] を false に戻す (次に見せるには、テスト側が改めて true に
/// 戻して「先読みが完了した」ことを表す)。
class FakeAdGateway implements AdGateway {
  bool ready;
  int initCount = 0;
  int preloadCount = 0;
  int showCount = 0;
  bool disposed = false;

  FakeAdGateway({this.ready = true});

  @override
  Future<void> init() async {
    initCount++;
  }

  @override
  Future<void> preload() async {
    preloadCount++;
  }

  @override
  bool get isAdReady => ready;

  @override
  Future<void> showIfAvailable() async {
    if (!ready) return;
    showCount++;
    ready = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// テスト用の [BillingGateway] 偽実装。
///
/// [products] が [queryProducts] の戻り値になる。[buy] / [restorePurchases]
/// は呼ばれたことだけを記録し、結果は返さない -- 実物の `in_app_purchase`
/// と同じく、購入の結果は同期的な戻り値ではなく [purchaseUpdates] に非同期で
/// 届く。テストは [emit] で好きなタイミング・好きな内容の
/// [PurchaseUpdate] を流し込める。
class FakeBillingGateway implements BillingGateway {
  List<BillingProduct> products;
  final List<String> buyCalls = [];
  int restoreCalls = 0;
  bool disposed = false;

  /// Set by a test that wants to observe the screen's loading state before
  /// deciding what [queryProducts] resolves to. When null (the default),
  /// [queryProducts] resolves to [products] right away.
  Completer<List<BillingProduct>>? pendingQuery;

  final StreamController<PurchaseUpdate> _updates =
      StreamController<PurchaseUpdate>.broadcast();
  final StreamController<String> _entitlements =
      StreamController<String>.broadcast();

  FakeBillingGateway({this.products = const []});

  @override
  Future<void> init() async {}

  @override
  Future<List<BillingProduct>> queryProducts() async {
    final pending = pendingQuery;
    if (pending != null) return pending.future;
    return products;
  }

  @override
  Future<bool> buy(String productId) async {
    buyCalls.add(productId);
    return products.any((p) => p.id == productId);
  }

  /// [restorePurchases] が呼ばれた瞬間に流す更新。ストアが「この人が既に
  /// 持っている購入」として返してくるものに相当する。
  List<PurchaseUpdate> restoreResults = const [];

  /// 設定すると [restorePurchases] がこれを投げる（ストアに繋がらない等）。
  Object? restoreError;

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
    final error = restoreError;
    if (error != null) throw error;
    restoreResults.forEach(emit);
  }

  int syncCalls = 0;

  /// [syncPurchases] が呼ばれた瞬間に流す更新。起動時の同期でストアが
  /// 返してくる「既に持っている購入」に相当する。
  List<PurchaseUpdate> syncResults = const [];

  /// 設定すると [syncPurchases] がこれを投げる（ストアに繋がらない端末）。
  Object? syncError;

  @override
  Future<void> syncPurchases() async {
    syncCalls++;
    final error = syncError;
    if (error != null) throw error;
    syncResults.forEach(emit);
  }

  @override
  Stream<PurchaseUpdate> get purchaseUpdates => _updates.stream;

  @override
  Stream<String> get entitlementChanges => _entitlements.stream;

  /// [purchaseUpdates] （と、granted なら [entitlementChanges] にも）
  /// [update] を流し込む。実物の `IoBillingGateway._emit` に相当するテスト
  /// 側の差し込み口。
  void emit(PurchaseUpdate update) {
    _updates.add(update);
    if (update.outcome == PurchaseOutcome.granted) {
      _entitlements.add(update.productId);
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _updates.close();
    await _entitlements.close();
  }
}
