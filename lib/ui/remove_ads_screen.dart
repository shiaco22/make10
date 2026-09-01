import 'dart:async';

import 'package:flutter/material.dart';

import '../data/entitlement_repository.dart';
import '../data/models/entitlement.dart';
import '../monetization/billing/billing_gateway.dart';
import 'widgets/responsive.dart';

/// 広告除去を購入する画面。ホーム画面から遷移する。
///
/// [billing] と [entitlements] はどちらも呼び出し側が用意した具体的な
/// インスタンスを受け取るだけ（StatsScreen が StatsRepository を受け取る
/// のと同じパターン）。Riverpod を直接参照しないので、テストは
/// `MaterialApp(home: RemoveAdsScreen(billing: fake, entitlements: repo))`
/// の形で偽のゲートウェイを直接差し込める。
///
/// [entitlements] は [ChangeNotifier] なので、購入や restore が成立した
/// 瞬間にこの画面自身が「購入済み」表示へ切り替わる（ホームへ戻るのを
/// 待たない）。
class RemoveAdsScreen extends StatefulWidget {
  final BillingGateway billing;
  final EntitlementRepository entitlements;

  const RemoveAdsScreen({
    super.key,
    required this.billing,
    required this.entitlements,
  });

  @override
  State<RemoveAdsScreen> createState() => _RemoveAdsScreenState();
}

class _RemoveAdsScreenState extends State<RemoveAdsScreen> {
  /// null の間はストアへの問い合わせ中（初回・再試行とも）。
  List<BillingProduct>? _products;

  /// buy() を呼んでから、その商品について何か終端の更新
  /// （granted/canceled/failed）か pending が届くまでの間 true にする商品 ID。
  /// ボタンの二重タップ防止と、進行中スピナー表示に使う。
  final Set<String> _inFlight = {};

  /// 直近に届いた購入更新。ステータス行の表示に使う。
  PurchaseUpdate? _lastUpdate;

  bool _restoring = false;

  StreamSubscription<PurchaseUpdate>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.billing.purchaseUpdates.listen(_onPurchaseUpdate);
    widget.entitlements.addListener(_onEntitlementChanged);
    _loadProducts();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.entitlements.removeListener(_onEntitlementChanged);
    super.dispose();
  }

  void _onEntitlementChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProducts() async {
    setState(() => _products = null);
    final products = await widget.billing.queryProducts();
    if (!mounted) return;
    setState(() => _products = products);
  }

  void _onPurchaseUpdate(PurchaseUpdate update) {
    if (!ProductIds.all.contains(update.productId)) return;
    if (!mounted) return;
    setState(() {
      _lastUpdate = update;
      if (update.outcome != PurchaseOutcome.pending) {
        _inFlight.remove(update.productId);
      }
    });
    if (update.outcome == PurchaseOutcome.granted) {
      if (update.productId == ProductIds.noAdsLifetime) {
        widget.entitlements.grantLifetime();
      } else if (update.productId == ProductIds.noAdsMonthly) {
        widget.entitlements.grantMonthly();
      }
    }
  }

  Future<void> _buy(BillingProduct product) async {
    setState(() {
      _inFlight.add(product.id);
      _lastUpdate = null;
    });
    final started = await widget.billing.buy(product.id);
    if (!started && mounted) {
      setState(() {
        _inFlight.remove(product.id);
        _lastUpdate = PurchaseUpdate(
          productId: product.id,
          outcome: PurchaseOutcome.failed,
          errorMessage: '購入を開始できませんでした',
        );
      });
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    await widget.billing.restorePurchases();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('広告を消す')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(child: _buildProductsArea(context)),
              const SizedBox(height: 16),
              // Apple requires restore to always be reachable, so this lives
              // outside the products-dependent area below -- it stays put
              // whether the store query is still loading, came back empty,
              // or is fully loaded.
              Center(
                child: TextButton(
                  onPressed: _restoring ? null : _restore,
                  child: Text(_restoring ? '復元中…' : '購入を復元'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsArea(BuildContext context) {
    final products = _products;
    if (products == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ストアに接続できませんでした'),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadProducts, child: const Text('再試行')),
          ],
        ),
      );
    }

    final scale = uiScale(context);
    final entitled = widget.entitlements.isEntitled();
    return ListView(
      children: [
        if (entitled)
          _entitledBanner()
        else
          for (final product in products) _productTile(product, scale),
        const SizedBox(height: 16),
        _statusLine(),
      ],
    );
  }

  Widget _entitledBanner() {
    final source = widget.entitlements.state.source;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('現在「${source.label}」が有効です。広告は表示されません。'),
      ),
    );
  }

  Widget _productTile(BillingProduct product, double scale) {
    final busy = _inFlight.contains(product.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(product.title),
        subtitle: Text(product.formattedPrice),
        trailing: SizedBox(
          height: 40 * scale,
          child: FilledButton(
            onPressed: busy ? null : () => _buy(product),
            child: busy
                ? SizedBox(
                    width: 16 * scale,
                    height: 16 * scale,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('購入'),
          ),
        ),
      ),
    );
  }

  Widget _statusLine() {
    final update = _lastUpdate;
    if (update == null) return const SizedBox.shrink();
    switch (update.outcome) {
      case PurchaseOutcome.pending:
        return const Text('処理中です…');
      case PurchaseOutcome.granted:
        // entitled バナーが既にこの状態を表しているので、二重表示しない。
        return const SizedBox.shrink();
      case PurchaseOutcome.canceled:
        return const Text('購入をキャンセルしました');
      case PurchaseOutcome.failed:
        final detail = update.errorMessage;
        return Text(
          detail == null ? '購入できませんでした' : '購入できませんでした: $detail',
        );
    }
  }
}
