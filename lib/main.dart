import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/entitlement_repository.dart';
import 'game/providers.dart';
import 'monetization/ads/ad_gateway.dart';
import 'monetization/billing/billing_gateway.dart';
import 'ui/app.dart';

/// 起動処理のうち「失敗してもゲームは遊べる」部分を包む。
///
/// パズルの出題・採点・統計は端末内で完結していて、広告にも課金にも依存
/// しない。にもかかわらず、以前はここが例外を投げると [runApp] に到達せず、
/// **アプリが一度も画面を出せないまま落ちていた**。Google Play 開発者
/// サービスが無い端末（GMS 非搭載の Huawei 端末など）や、Play ストアが
/// 使えない状態では、初期化が失敗しうる。
///
/// そのような端末では「広告なし・購入不可のオフラインゲーム」として動くのが
/// 正しい姿で、起動不能は明確な不具合。失敗はログに出すだけで握り潰す。
Future<void> _tolerate(String what, Future<void> Function() action) async {
  try {
    await action();
  } catch (error, stackTrace) {
    debugPrint('MAKE10: $what の初期化に失敗しました（続行します）: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // エンタイトルメントを読み込み、課金ゲートウェイの購読をなるべく早く
  // 始める（メインの Widget を返すより前に、が in_app_purchase の推奨 --
  // BillingGateway.init() のクラス doc 参照）。ここで作った2つのインスタンス
  // をそのまま ProviderScope の override に渡すことで、この購読が実際に
  // 反映する先 (entitlements) と、画面が読みに行く先
  // (entitlementRepositoryProvider) を同じインスタンスに揃える -- 別々の
  // インスタンスになると、ここで拾った購入がホーム画面には一生反映されない。
  //
  // どれも失敗しうるが、失敗しても [runApp] までは必ず進む（[_tolerate]）。
  final entitlements = EntitlementRepository();
  await _tolerate('エンタイトルメントの読み込み', entitlements.load);

  final billing = createBillingGateway();
  await _tolerate('課金', billing.init);
  // init() が失敗していても entitlementChanges 自体は購読できる
  // （実装側で先に作られる StreamController なので、購入が流れてこないだけ）。
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
  unawaited(_tolerate('広告', ads.init));

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
