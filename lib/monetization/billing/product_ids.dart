/// 広告を消す 2 つの商品 ID。ストア（Google Play Console / App Store Connect）
/// 側の商品設定と一致させること。単一のソースにしておき、あちこちに
/// 文字列リテラルで散らばらせない。
class ProductIds {
  ProductIds._();

  /// 月額購読。ベースプラン ID は `monthly`（Google Play Console 側の設定）。
  /// ¥300/月。
  static const String noAdsMonthly = 'make10_noads_monthly';

  /// 買い切り。¥980。
  static const String noAdsLifetime = 'make10_noads_lifetime';

  static const Set<String> all = {noAdsMonthly, noAdsLifetime};
}
