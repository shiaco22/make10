import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/entitlement_repository.dart';
import 'game/providers.dart';
import 'monetization/ads/ad_gateway.dart';
import 'monetization/billing/billing_gateway.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // エンタイトルメントを読み込み、課金ゲートウェイの購読をなるべく早く
  // 始める（メインの Widget を返すより前に、が in_app_purchase の推奨 --
  // BillingGateway.init() のクラス doc 参照）。ここで作った2つのインスタンス
  // をそのまま ProviderScope の override に渡すことで、この購読が実際に
  // 反映する先 (entitlements) と、画面が読みに行く先
  // (entitlementRepositoryProvider) を同じインスタンスに揃える -- 別々の
  // インスタンスになると、ここで拾った購入がホーム画面には一生反映されない。
  final entitlements = EntitlementRepository();
  await entitlements.load();
  final billing = createBillingGateway();
  await billing.init();
  billing.entitlementChanges.listen((productId) {
    if (productId == ProductIds.noAdsLifetime) {
      unawaited(entitlements.grantLifetime());
    } else if (productId == ProductIds.noAdsMonthly) {
      unawaited(entitlements.grantMonthly());
    }
  });

  // 広告の初期化はアプリの起動を待たせない (fire-and-forget)。先読みが
  // 間に合わなければ、その回はただ広告なしで進む -- ゲームプレイは
  // 広告の読み込みを待ってはいけないという契約は AdGateway 自身が担うので、
  // ここでは単に呼びっぱなしにするだけでよい。
  final ads = createAdGateway();
  unawaited(ads.init());

  // 画面の向き（縦向き固定 or 自由回転）の決定は Make10App.build() 側で行う
  // （仕様 §9.2）。ここではまだ MediaQuery が存在せず、電話かタブレットかを
  // 判定する基準（ビューポートの短辺）を読めないため。
  runApp(
    ProviderScope(
      overrides: [
        entitlementRepositoryProvider.overrideWith((ref) => entitlements),
        billingGatewayProvider.overrideWithValue(billing),
        adGatewayProvider.overrideWithValue(ads),
      ],
      child: const Make10App(),
    ),
  );
}
