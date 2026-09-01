import 'product_ids.dart';

// プラグイン（in_app_purchase）は Android/iOS 専用。Web ビルドがこの
// プラグインを一切参照しないよう、実装の選択は conditional import で行う —
// `dart.library.io` が使えるとき（Android/iOS/デスクトップ/`flutter test` の
// VM 実行）は `billing_gateway_io.dart`、使えないとき（Web）は
// `billing_gateway_web.dart` にフォールバックする。
//
// このファイル自身はどちらの実装ファイルが選ばれても import されるため、
// プラグインへの参照を一切含めてはいけない。
import 'billing_gateway_web.dart' if (dart.library.io) 'billing_gateway_io.dart' as platform;

export 'product_ids.dart';

/// アプリの語彙に翻訳したストアの商品情報。呼び出し側が `in_app_purchase` の
/// 型を直接扱わずに済むようにするため。
class BillingProduct {
  final String id;
  final String title;
  final String formattedPrice;

  const BillingProduct({
    required this.id,
    required this.title,
    required this.formattedPrice,
  });
}

/// 1 件の購入（新規購入・restore の両方）が今どういう状態か。
///
/// `in_app_purchase` の `PurchaseStatus`（pending / purchased / error /
/// restored / canceled）をここに畳み込む。`purchased` と `restored` は
/// どちらも [granted] になり、[PurchaseUpdate.isRestore] で区別する。
enum PurchaseOutcome {
  /// 処理中（ユーザーの承認待ちなど）。まだ何も確定していない。
  pending,

  /// 購入が成立した。エンタイトルメントを与えてよい。
  granted,

  /// ユーザーが購入をキャンセルした。
  canceled,

  /// 決済エラーで購入が成立しなかった。
  failed,
}

/// 購入ストリームの 1 件の更新。UI 側のフィードバック（「購入できません
/// でした」等）に使うことを想定し、[granted] 以外の状態も含めて全件流す。
class PurchaseUpdate {
  final String productId;
  final PurchaseOutcome outcome;

  /// 新規購入ではなく [BillingGateway.restorePurchases] によるものか。
  final bool isRestore;

  /// [PurchaseOutcome.failed] のときの人間可読なメッセージ（あれば）。
  final String? errorMessage;

  const PurchaseUpdate({
    required this.productId,
    required this.outcome,
    this.isRestore = false,
    this.errorMessage,
  });

  @override
  String toString() =>
      'PurchaseUpdate(productId: $productId, outcome: $outcome, isRestore: $isRestore, errorMessage: $errorMessage)';
}

/// プラットフォームの課金 SDK（`in_app_purchase`）をラップするゲートウェイ。
/// Android/iOS 専用 — Web では [createBillingGateway] が常に
/// `WebBillingGateway`（何も課金しない実装）を返す。
///
/// **ローカル検証のみ**: このゲートウェイも、それを使う
/// `EntitlementRepository` も、購入をサーバーで検証しない。詳しくは
/// `EntitlementRepository` のクラス doc を参照。
abstract class BillingGateway {
  /// 起動時に一度だけ呼ぶ。[purchaseUpdates] の購読を開始する。
  ///
  /// ドキュメント上も「アプリ起動後、なるべく早く（メインの Widget を
  /// 返すより前に）購読を始めること」が推奨されている —
  /// 起動前に確定した購入の更新を取りこぼさないため。
  Future<void> init();

  /// [ProductIds.all] の 2 商品をストアに問い合わせる。ストアが認識しない
  /// 商品（Play Console 未設定など）は結果に含まれず、黙って除外される。
  Future<List<BillingProduct>> queryProducts();

  /// [productId] の購入を開始する。[queryProducts] で得られていない ID を
  /// 渡した場合は何もせず false を返す — ストアの商品情報なしに購入フローは
  /// 開始できないため。
  ///
  /// 戻り値は「購入リクエストを送れたか」だけを表す。購入そのものの結果
  /// （成功・保留・失敗）はこの戻り値ではなく [purchaseUpdates] に届く —
  /// ストアは購入を同期的には確定させない。
  Future<bool> buy(String productId);

  /// ストアに問い合わせて、ユーザーが既に保有している購入を再取得する。
  /// 結果は個別の [PurchaseUpdate]（[PurchaseUpdate.isRestore] が true）と
  /// して [purchaseUpdates] に届く。
  Future<void> restorePurchases();

  /// 両商品について、状態が変わるたびに 1 件ずつ届く。pending / canceled /
  /// failed も含む全件。
  Stream<PurchaseUpdate> get purchaseUpdates;

  /// [purchaseUpdates] のうち、実際にエンタイトルメントを与える
  /// （[PurchaseOutcome.granted]）ものだけを、商品 ID として流す部分集合。
  ///
  /// これは**ライブな信号でしかない**——このゲートウェイは購読の有効期限を
  /// 一切知らない（`in_app_purchase` 自体が失効日を教えてくれない）。
  /// 「いつまで信用するか」を決めて保存するのは呼び出し側
  /// （`EntitlementRepository`）の仕事。
  Stream<String> get entitlementChanges;

  /// ストリーム購読の解放など、後片付け。
  Future<void> dispose();
}

/// Android/iOS では `in_app_purchase` をラップした実装を、Web では常に
/// 「何も課金しない」実装を返す。
BillingGateway createBillingGateway() => platform.createBillingGateway();
