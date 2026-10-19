import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/entitlement_repository.dart';
import 'billing_gateway.dart';

/// 課金ゲートウェイが知らせる権利を [entitlements] に反映し始め、続けて
/// ストアとの起動時同期（[BillingGateway.syncPurchases]）を走らせる。
///
/// 順序に意味がある。購読より先に同期すると、同期で届いた購入が誰にも
/// 拾われずに消える（[BillingGateway.entitlementChanges] はブロード
/// キャストで、聞き手がいない間の更新は残らない）。
///
/// 同期は待たない — 起動を遅らせないため。失敗してもログに残すだけで、
/// 呼び出し側には投げない。端末に保存済みの権利がそのまま使われる。
StreamSubscription<String> startEntitlementSync({
  required BillingGateway billing,
  required EntitlementRepository entitlements,
}) {
  final subscription = billing.entitlementChanges.listen((productId) {
    if (productId == ProductIds.noAdsLifetime) {
      unawaited(entitlements.grantLifetime());
    } else if (productId == ProductIds.noAdsMonthly) {
      unawaited(entitlements.grantMonthly());
    }
  });
  unawaited(
    billing.syncPurchases().catchError((Object error) {
      debugPrint('MAKE10: 起動時の購入同期に失敗しました（無視します）: $error');
    }),
  );
  return subscription;
}
