import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// AdMob の ID を一箇所にまとめる、唯一の定義元。
///
/// ## このファイルで `dart:io` を使える理由
///
/// このファイルを import しているのは `ad_gateway_io.dart` だけで、それも
/// `ad_gateway.dart` の `dart.library.io` conditional import 経由でしか
/// 選ばれない（Web ビルドでは代わりに `ad_gateway_web.dart` が選ばれ、
/// そちらはこのファイルを一切参照しない）。つまりこのファイルは Web
/// バンドルに含まれないので、`dart:io` の [Platform] をここで安全に使える。
///
/// ## Android と iOS で ID が違う理由
///
/// AdMob はプラットフォームごとに別々の「アプリ」としてアプリ ID・広告
/// ユニット ID を発行する。**Android はプロダクトオーナーから本番 ID を
/// 受領済み**（AdMob アプリ ID・インタースティシャル広告ユニット ID
/// [`make10-interstitia`, フォーマット Interstitial] とも確認済み）。
/// **iOS 用の AdMob アプリはまだ登録されていない** — これは見落としでは
/// なく現状の事実。iOS 版はこれまでビルドも実行もされたことがなく
/// （macOS + Xcode が要る）、公開の予定も無いので、iOS は常に Google
/// 公式のテスト ID を返す。Android の本番 ID を iOS で使い回すのは誤設定
/// になる（AdMob はプラットフォームが違うアプリ ID/ユニット ID の組み
/// 合わせのリクエストを拒否しうるうえ、未検証のビルドの裏に実在の
/// パブリッシャーアカウントを晒すことになる）。iOS 用の本番定数はこの
/// ファイルに一切存在しない（存在しないこと自体が「未登録」を表す）。
///
/// [interstitialUnitId] はこの分岐を [Platform.isAndroid] で行う —
/// Android なら（[androidProductionIdsConfigured] が true の間）本番 ID、
/// それ以外（iOS はもちろん、デスクトップや `flutter test` の VM も含む）
/// は常にテスト ID。
///
/// ## `androidProductionIdsConfigured` について
///
/// 以前はプラットフォーム共通の1個のフラグ（`productionIdsConfigured`）が
/// 「本番 ID をまだ受け取っていない」状態を表していた（値は null、フラグは
/// false — 未設定のまま release ビルドに来て null を渡し即クラッシュする
/// 事故を防ぐため）。今は Android の値が確認済みの非 null 定数になったので、
/// Android について「null が本番ビルドに届く」事故は型システムが
/// 構造的に防ぐ。フラグ自体は Android 専用に改名 (`androidProductionIdsConfigured`)
/// して残してある。理由:
/// 1. 値を消さずに Android だけ即座にテスト広告へ切り戻せる、運用上の
///    キルスイッチとして使える
/// 2. 「確認済みで意図的に有効化した」という記録をコード上の1箇所に残せる
///
/// iOS には対応する本番定数がそもそも存在しないので、このフラグを
/// 誤って true のままにしても iOS が Android の値を読むことは構造的に
/// 起こらない — [Platform.isAndroid] のチェックと二重にガードされている。
///
/// ## テストでの上書き
///
/// `flutter test` は実機ではなくホスト OS 上の VM で動くため、
/// [Platform.isAndroid] は常にこの実行環境（Windows 上では false）の
/// 判定になる。Android・iOS 両方の分岐を実際に検証できるように、
/// [interstitialUnitIdFor] がテスト専用の `isAndroid` 引数を公開している
/// （`test/monetization/ads/ad_unit_ids_test.dart` を参照）。
///
/// ## Android の広告ユニットを差し替える／増やすとき
/// 1. 値を [_prodAndroidInterstitialUnitId] に設定する
/// 2. `android/app/src/main/AndroidManifest.xml` の
///    `com.google.android.gms.ads.APPLICATION_ID` が [androidAppId] と
///    一致していることを確認する（AdMob の Android アプリ ID は起動時に
///    読まれるマニフェスト静的値のため、実行時にここから切り替えることは
///    できない。値が欠落・不正だと起動時にクラッシュするので要注意）
///
/// ## iOS の AdMob アプリを登録したら
/// 1. AdMob で iOS アプリを新規登録し、インタースティシャル広告ユニットを
///    作る（Android のものを使い回すことはできない — AdMob はプラット
///    フォームごとに別アプリとして扱う）
/// 2. 受け取った iOS 用のアプリ ID と広告ユニット ID をこのファイルに追加し
///    （例: `_prodIosAppId`/`_prodIosInterstitialUnitId`）、
///    [interstitialUnitId] に iOS 用の本番分岐を足す
/// 3. `ios/Runner/Info.plist` の `GADApplicationIdentifier` を新しい iOS
///    アプリ ID に更新し、そこのコメントも書き換える
class AdUnitIds {
  AdUnitIds._();

  /// Google 公式のテスト用インタースティシャル広告ユニット ID。
  /// AdMob アカウントが無くても常に安全に使え、必ずテスト広告を返す。
  /// Android・iOS共通でそのまま使える。
  /// https://developers.google.com/admob/android/test-ads
  static const String testInterstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';

  /// Android 本番のインタースティシャル広告ユニット ID。プロダクトオーナー
  /// から受領・確認済み（AdMob 上のユニット名 `make10-interstitia`、
  /// フォーマット Interstitial）。iOS 用の本番 ID は存在しない — 理由は
  /// このクラスの doc コメント参照。
  static const String _prodAndroidInterstitialUnitId =
      'ca-app-pub-2873615858472032/2546502748';

  /// Android の本番 ID が確認済みで、意図的に有効化されていることを示す
  /// フラグ。false に戻せば、値はそのままに Android だけ即座にテスト広告へ
  /// 切り戻せる（クラス doc コメント参照）。iOS の分岐には一切関与しない。
  static const bool androidProductionIdsConfigured = true;

  /// [interstitialUnitId] の実体。`isAndroid` はテスト専用の上書き入口 —
  /// 省略時は実機の [Platform.isAndroid] をそのまま使う。
  ///
  /// - Android（かつ [androidProductionIdsConfigured] が true）: 本番 ID
  /// - それ以外（iOS を含む）: 常にテスト ID
  @visibleForTesting
  static String interstitialUnitIdFor({bool? isAndroid}) {
    final android = isAndroid ?? Platform.isAndroid;
    if (android && androidProductionIdsConfigured) {
      return _prodAndroidInterstitialUnitId;
    }
    return testInterstitialUnitId;
  }

  /// 読み込む広告ユニット ID。実行中の実機判定に従う（[interstitialUnitIdFor]
  /// を参照）。
  static String get interstitialUnitId => interstitialUnitIdFor();

  /// Google 公式のテスト用 AdMob アプリ ID。Android・iOS共通で安全に使える。
  /// https://developers.google.com/admob/android/test-ads#sample_ad_units
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// 本番の AdMob Android アプリ ID。プロダクトオーナーから受領・確認済み。
  static const String _prodAndroidAppId = 'ca-app-pub-2873615858472032~3841448717';

  /// `android/app/src/main/AndroidManifest.xml` の
  /// `com.google.android.gms.ads.APPLICATION_ID` に書き写す値
  /// （マニフェストは静的ファイルなので、この getter を Dart 側から実行時に
  /// 読ませることはできない — このファイルを「正」として手動で同期し、
  /// `test/platform/manifest_xml_test.dart` がズレを検知する）。
  ///
  /// [androidProductionIdsConfigured] にのみ従う（プラットフォーム判定はしない
  /// — この値の唯一の用途は Android 自身のマニフェストとの同期であり、
  /// 「今どのプラットフォームで動いているか」は無関係）。
  ///
  /// iOS の `Info.plist` はこの値を一切参照しない。iOS 用の AdMob アプリが
  /// 存在しないため、`Info.plist` は自分自身のテスト ID
  /// （[testAppId] と同じ値）を直接保持している（`ios/Runner/Info.plist` の
  /// コメント参照）。Android のこの値を iOS へ使い回すのは誤設定になる —
  /// このクラスの doc コメント参照。
  static String get androidAppId =>
      androidProductionIdsConfigured ? _prodAndroidAppId : testAppId;
}
