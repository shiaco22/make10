import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ad_policy_repository.dart';
import '../data/entitlement_repository.dart';
import '../data/history_repository.dart';
import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';
import '../domain/ad_policy.dart';
import '../monetization/ads/ad_gateway.dart';
import '../monetization/billing/billing_gateway.dart';
import 'interstitial_ad_coordinator.dart';

final historyRepositoryProvider = FutureProvider<HistoryRepository>((ref) async {
  final repo = HistoryRepository();
  await repo.load();
  return repo;
});

final statsRepositoryProvider = FutureProvider<StatsRepository>((ref) async {
  final repo = StatsRepository();
  await repo.load();
  return repo;
});

final puzzleRepositoryProvider = FutureProvider<PuzzleRepository>((ref) async {
  final history = await ref.watch(historyRepositoryProvider.future);
  final repo = PuzzleRepository(history);
  await repo.loadFromAsset();
  return repo;
});

/// 広告除去のエンタイトルメント。端末内の shared_preferences だけで判定する
/// （EntitlementRepository のクラス doc 参照）。
final entitlementRepositoryProvider =
    FutureProvider<EntitlementRepository>((ref) async {
  final repo = EntitlementRepository();
  await repo.load();
  return repo;
});

/// [AdPolicy.clearsSinceLastAd] の永続化先。
final adPolicyRepositoryProvider =
    FutureProvider<AdPolicyRepository>((ref) async {
  final repo = AdPolicyRepository();
  await repo.load();
  return repo;
});

/// アプリ全体で共有する1つの [AdGateway]。生成するだけで `init()` は
/// 呼ばない -- `init()` は実機・実配信でのみ意味を持つ副作用（AdMob SDK の
/// 初期化と最初の先読み）であり、`main()` がアプリ起動時に明示的に1回だけ
/// 呼び、既に初期化済みのインスタンスをこのプロバイダへ上書きする
/// （main.dart 参照）。テストがそれを上書きしない限りここで作られるのは
/// 「何も読み込んでいない」ゲートウェイで、[AdGateway.isAdReady] は常に
/// false、[AdGateway.showIfAvailable] は即座に戻る -- `flutter test` が
/// 本物のプラグインのメソッドチャネルに触れることは無い。
final adGatewayProvider = Provider<AdGateway>((ref) {
  final gateway = createAdGateway();
  ref.onDispose(() => gateway.dispose());
  return gateway;
});

/// [adGatewayProvider] と同じ考え方の、課金ゲートウェイ版。
final billingGatewayProvider = Provider<BillingGateway>((ref) {
  final gateway = createBillingGateway();
  ref.onDispose(() => gateway.dispose());
  return gateway;
});

/// インタースティシャル表示の判断・実行・永続化をまとめた調整役。
/// アプリの寿命の間キャッシュされる1インスタンスとして扱う
/// （`InterstitialAdCoordinator` のクラス doc 参照）。
final interstitialAdCoordinatorProvider =
    FutureProvider<InterstitialAdCoordinator>((ref) async {
  final adPolicyRepo = await ref.watch(adPolicyRepositoryProvider.future);
  final entitlements = await ref.watch(entitlementRepositoryProvider.future);
  final gateway = ref.watch(adGatewayProvider);
  return InterstitialAdCoordinator(
    policy: AdPolicy(initialClearsSinceLastAd: adPolicyRepo.clearsSinceLastAd),
    gateway: gateway,
    entitlements: entitlements,
    persistClearsSinceLastAd: adPolicyRepo.save,
  );
});
