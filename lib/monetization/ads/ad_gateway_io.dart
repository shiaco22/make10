import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_gateway.dart';
import 'ad_unit_ids.dart';

/// Android/iOS 版の広告ゲートウェイ。`google_mobile_ads` を薄くラップする。
///
/// `google_mobile_ads` はメソッドチャンネルを直接使う実装で、
/// `in_app_purchase` のようなフェデレーテッド・プラットフォームインター
/// フェースは公開していない。そのため、このクラスの内部（実際の
/// `InterstitialAd.load`/`show` 呼び出し）をユニットテストで安全に
/// 差し替える公式な手段が無い —
/// `test/monetization/ads/ad_gateway_io_test.dart` はコンパイルが通る
/// ことと、プラグイン呼び出しに触れないゲッター（[isAdReady]・
/// [dispose]（未読み込み時））だけを検証する。実際の広告表示は手動確認
/// （テスト広告ユニットを使った実機/エミュレータ確認）に委ねる。
class IoAdGateway implements AdGateway {
  InterstitialAd? _ad;
  bool _isLoading = false;
  bool _disposed = false;

  @override
  Future<void> init() async {
    await MobileAds.instance.initialize();
    await preload();
  }

  @override
  Future<void> preload() async {
    if (_disposed || _isLoading || _ad != null) return;
    _isLoading = true;
    await InterstitialAd.load(
      adUnitId: AdUnitIds.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoading = false;
          if (_disposed) {
            // dispose() がロード完了より先に走っていたら、この広告は
            // 使われないので即座に解放する。
            unawaited(ad.dispose());
            return;
          }
          _ad = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
            onAdDismissedFullScreenContent: _onAdFinished,
            onAdFailedToShowFullScreenContent: (ad, error) => _onAdFinished(ad),
          );
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          // ここでリトライループを組まない — 次に preload/showIfAvailable
          // が呼ばれたときに自然にもう一度試すので十分（ゲームプレイを
          // 広告の再試行で塞がないことを優先する）。
        },
      ),
    );
  }

  void _onAdFinished(InterstitialAd ad) {
    unawaited(ad.dispose());
    if (identical(_ad, ad)) {
      _ad = null;
    }
    // 次回のために先読みしておく。結果は待たない。
    unawaited(preload());
  }

  @override
  bool get isAdReady => _ad != null;

  @override
  Future<void> showIfAvailable() async {
    final ad = _ad;
    if (ad == null) {
      // 読み込みが間に合っていない — ゲームプレイを待たせず、黙って
      // スキップする。
      return;
    }
    _ad = null; // 表示中に二重に show() されるのを防ぐ。
    await ad.show();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final ad = _ad;
    _ad = null;
    await ad?.dispose();
  }
}

AdGateway createAdGateway() => IoAdGateway();
