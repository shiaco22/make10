/// AdMob の ID を一箇所にまとめる、唯一の定義元。
///
/// Google が公開しているテスト ID は AdMob アカウントが無くても常に安全に
/// 使え、必ずテスト広告を返す。本番 ID がまだ受け取れていない間は、
/// 常にこのテスト ID を使う ([productionIdsConfigured] が false の間は
/// [interstitialUnitId] が本番 ID を一切参照しない) — デバッグ/リリースの
/// ビルド種別で自動的に切り替える方式は採らない。本番 ID が未設定のまま
/// リリースビルドに来ると、null を渡して即クラッシュになりかねないため。
///
/// 本番 ID を受け取ったら:
/// 1. [_prodInterstitialUnitId] に設定する
/// 2. [productionIdsConfigured] を true にする
/// 3. `android/app/src/main/AndroidManifest.xml` の
///    `com.google.android.gms.ads.APPLICATION_ID` を [androidAppId] と
///    一致させる（AdMob の Android アプリ ID は起動時に読まれるマニフェスト
///    静的値のため、実行時にここから切り替えることはできない。値が
///    欠落・不正だと起動時にクラッシュするので要注意）
class AdUnitIds {
  AdUnitIds._();

  /// Google 公式のテスト用インタースティシャル広告ユニット ID。
  /// https://developers.google.com/admob/android/test-ads
  static const String _testInterstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';

  /// 本番のインタースティシャル広告ユニット ID。プロダクトオーナーから
  /// まだ受領していない — 未設定のマーカーとして null のままにしてある。
  static const String? _prodInterstitialUnitId = null;

  /// [_prodInterstitialUnitId] が実際の値になったら true にする。
  static const bool productionIdsConfigured = false;

  /// 読み込む広告ユニット ID。本番 ID が未設定の間は必ずテスト ID になる。
  static String get interstitialUnitId {
    final prod = _prodInterstitialUnitId;
    if (productionIdsConfigured && prod != null) return prod;
    return _testInterstitialUnitId;
  }

  /// Google 公式のテスト用 AdMob アプリ ID。
  /// https://developers.google.com/admob/android/test-ads#sample_ad_units
  static const String _testAndroidAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// 本番の AdMob Android アプリ ID。まだ未受領。
  static const String? _prodAndroidAppId = null;

  /// `android/app/src/main/AndroidManifest.xml` の
  /// `com.google.android.gms.ads.APPLICATION_ID` に書き写す値。
  /// マニフェストは静的ファイルなので、この getter を Dart 側から実行時に
  /// 読ませることはできない — このファイルを「正」として手動で同期する。
  static String get androidAppId {
    final prod = _prodAndroidAppId;
    if (productionIdsConfigured && prod != null) return prod;
    return _testAndroidAppId;
  }
}
