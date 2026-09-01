/// AdMob の ID を一箇所にまとめる、唯一の定義元。
///
/// Google が公開しているテスト ID は AdMob アカウントが無くても常に安全に
/// 使え、必ずテスト広告を返す。本番 ID がまだ受け取れていない間は、
/// 常にこのテスト ID を使う ([productionIdsConfigured] が false の間は
/// [interstitialUnitId] が本番 ID を一切参照しない) — デバッグ/リリースの
/// ビルド種別で自動的に切り替える方式は採らない。本番 ID が未設定のまま
/// リリースビルドに来ると、null を渡して即クラッシュになりかねないため。
///
/// Android の本番 ID は設定済み（2026-09-01 受領）。`AndroidManifest.xml` の
/// `com.google.android.gms.ads.APPLICATION_ID` も [androidAppId] と一致させて
/// ある。AdMob の Android アプリ ID は起動時に読まれるマニフェスト静的値の
/// ため、実行時にここから切り替えることはできない。値が欠落・不正だと起動時に
/// クラッシュするので、片方だけ変えないこと。
///
/// **iOS はまだ本番 ID を持っていない。** AdMob のアプリ ID と広告ユニット ID は
/// プラットフォームごとに別で、ここにあるのは Android 用のものだけ。
/// `Info.plist` は Google のテスト ID のままにしてあるが、
/// [productionIdsConfigured] が true になった今、iOS ビルドは
/// [interstitialUnitId] から Android の広告ユニットを読みにいく。Android 単独
/// リリースの間は実害がないが、**iOS を出す前に、iOS 用のアプリを AdMob で
/// 登録し、このクラスをプラットフォームで分岐させること。**
class AdUnitIds {
  AdUnitIds._();

  /// Google 公式のテスト用インタースティシャル広告ユニット ID。
  /// https://developers.google.com/admob/android/test-ads
  static const String _testInterstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';

  /// 本番の Android インタースティシャル広告ユニット ID。
  static const String? _prodInterstitialUnitId = 'ca-app-pub-2873615858472032/2546502748';

  /// [_prodInterstitialUnitId] が実際の値になったら true にする。
  static const bool productionIdsConfigured = true;

  /// 読み込む広告ユニット ID。本番 ID が未設定の間は必ずテスト ID になる。
  static String get interstitialUnitId {
    final prod = _prodInterstitialUnitId;
    if (productionIdsConfigured && prod != null) return prod;
    return _testInterstitialUnitId;
  }

  /// Google 公式のテスト用 AdMob アプリ ID。
  /// https://developers.google.com/admob/android/test-ads#sample_ad_units
  static const String _testAndroidAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// 本番の AdMob Android アプリ ID。
  static const String? _prodAndroidAppId = 'ca-app-pub-2873615858472032~3841448717';

  /// `android/app/src/main/AndroidManifest.xml` の
  /// `com.google.android.gms.ads.APPLICATION_ID` に書き写す値。静的ファイルな
  /// ので、この getter を Dart 側から実行時に読ませることはできない。この
  /// ファイルを「正」として手動で同期する。
  ///
  /// `ios/Runner/Info.plist` の `GADApplicationIdentifier` は**この値では
  /// ない**。テスト ID を共有していた頃はそうしていたが、本番の AdMob アプリ
  /// ID は Android と iOS で別物になる。クラス冒頭の注記を参照。
  static String get androidAppId {
    final prod = _prodAndroidAppId;
    if (productionIdsConfigured && prod != null) return prod;
    return _testAndroidAppId;
  }
}
