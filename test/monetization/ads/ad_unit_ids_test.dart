import 'package:flutter_test/flutter_test.dart';
import 'package:make10/monetization/ads/ad_unit_ids.dart';

/// [AdUnitIds] の Android/iOS 分岐を検証する。
///
/// `flutter test` は実機ではなくホスト OS 上の VM で動くため、
/// `dart:io` の `Platform.isAndroid`/`Platform.isIOS` はこの実行環境
/// （Windows 上では両方 false）の判定に固定される。ホストの実プラット
/// フォームだけを暗黙に通すテストにしないよう、
/// [AdUnitIds.interstitialUnitIdFor] が公開しているテスト専用の `isAndroid`
/// 引数で Android・iOS 両方の分岐を明示的にシミュレートする。
void main() {
  group('interstitialUnitIdFor', () {
    test('Android では本番のインタースティシャル広告ユニット ID を返す', () {
      expect(
        AdUnitIds.interstitialUnitIdFor(isAndroid: true),
        'ca-app-pub-2873615858472032/2546502748',
      );
    });

    test(
        'iOS では常に Google 公式のテスト広告ユニット ID を返す '
        '(iOS 用の AdMob アプリが未登録のため。本番設定フラグの値に関わらず)', () {
      expect(
        AdUnitIds.interstitialUnitIdFor(isAndroid: false),
        AdUnitIds.testInterstitialUnitId,
      );
      expect(AdUnitIds.testInterstitialUnitId, 'ca-app-pub-3940256099942544/1033173712');
    });
  });

  test('interstitialUnitId (引数なし) はホストの実プラットフォーム判定に委譲する', () {
    // flutter test の実行環境 (VM) は Android ではないので、明示的に
    // isAndroid: false を渡した場合と同じ値になるはず -- 実機判定への
    // 委譲そのものを確かめる。
    expect(AdUnitIds.interstitialUnitId, AdUnitIds.interstitialUnitIdFor(isAndroid: false));
  });

  test('androidAppId は Android 本番の AdMob アプリ ID と一致する', () {
    // android/app/src/main/AndroidManifest.xml に手で同期する値そのもの
    // (test/platform/manifest_xml_test.dart が一致を検証する)。
    // プラットフォームに関わらず一定 -- iOS の Info.plist はこの値を
    // 参照せず、自分自身のテスト ID を直接保持している。
    expect(AdUnitIds.androidAppId, 'ca-app-pub-2873615858472032~3841448717');
  });

  test('Android の本番 ID は意図的に有効化されている', () {
    expect(AdUnitIds.androidProductionIdsConfigured, isTrue);
  });

  test('Google 公式のテスト ID (Android・iOS共通のフォールバック) は変わっていない', () {
    expect(AdUnitIds.testAppId, 'ca-app-pub-3940256099942544~3347511713');
    expect(AdUnitIds.testInterstitialUnitId, 'ca-app-pub-3940256099942544/1033173712');
  });
}
