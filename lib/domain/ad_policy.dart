/// インタースティシャル広告を「いつ出すか」だけを決める、プラットフォーム
/// 非依存のポリシー。プラグイン（google_mobile_ads）には一切触れない —
/// 実際に広告を読み込む・出すのは `lib/monetization/ads/` の `AdGateway` の
/// 役目で、ここは純粋な意思決定のみを扱う。
///
/// 採用した設計判断（詳細な理由はクラス末尾のコメントを参照）:
/// - カウンタ（[clearsSinceLastAd]）は**再起動をまたいで永続化する**。
///   このクラス自身は保存しない（プラグイン同様、shared_preferences にも
///   触れない）ので、呼び出し側が [clearsSinceLastAd] を読み出して保存し、
///   次回起動時に [AdPolicy.new] の `initialClearsSinceLastAd` として復元する。
/// - カウントするのは「クリア」だけ。スキップと答え表示は数えない。
/// - 広告を表示したら [onInterstitialShown] でカウンタを 0 に戻し、
///   次の 3 問区切りを再スタートする。
///
/// タイムアタックのクリアは [recordClear] に渡してもカウンタを進めない
/// （プラクティス統計に混ぜないのと同じ考え方 — 仕様 §8.2）。タイムアタックの
/// プレイ中は [shouldShowInterstitial] が [AdCheckpoint.puzzleCleared] を
/// 絶対に許可しない。リザルト画面（[AdCheckpoint.resultScreen]）でのみ、
/// エンタイトルメントの有無だけを見て許可する（3 問カウンタとは無関係 —
/// タイムアタックはプラクティスの「クリア」を積み上げないため、そもそも
/// このカウンタで測れない）。
enum GameMode { practice, timeAttack }

/// 広告を出してよいか呼び出す場所。
enum AdCheckpoint {
  /// パズルをクリアした直後（まだゲーム画面）。
  puzzleCleared,

  /// そのモードのリザルト画面。プラクティスにはリザルト画面が無いため、
  /// 実際に意味を持つのはタイムアタックだけ。
  resultScreen,
}

class AdPolicy {
  /// この数だけプラクティスをクリアするたびにインタースティシャルが妥当になる。
  static const int clearsPerInterstitial = 3;

  int _clearsSinceLastAd;

  /// [initialClearsSinceLastAd] は前回終了時に保存したカウンタの復元値。
  /// 省略時は 0（初回起動やカウンタ未保存時の既定値）。
  AdPolicy({int initialClearsSinceLastAd = 0})
      : assert(initialClearsSinceLastAd >= 0,
            'initialClearsSinceLastAd must not be negative'),
        _clearsSinceLastAd = initialClearsSinceLastAd;

  /// 直近の広告表示から数えた、プラクティスのクリア数。
  ///
  /// 呼び出し側が再起動をまたいで保存し、次回は `initialClearsSinceLastAd`
  /// として渡し直すことを想定した公開プロパティ。
  int get clearsSinceLastAd => _clearsSinceLastAd;

  /// 1 問クリアするたびに、モードを問わず呼ぶ。
  ///
  /// スキップした問題・答えを見た問題はそもそも「クリア」ではないので、
  /// 呼び出し側はこれらのイベントで [recordClear] を呼んではいけない
  /// （呼ばなければ、それだけでカウントから除外される）。
  void recordClear(GameMode mode) {
    if (mode == GameMode.practice) {
      _clearsSinceLastAd += 1;
    }
    // タイムアタックのクリアはカウントしない。タイムアタックは統計上も
    // practice の solved に混ぜない（仕様 §8.2）のと同じ理由: 120 秒で
    // 何問解けるかは「3 問ごと」という区切りの意味が違う。
  }

  /// 今この場所でインタースティシャルを出してよいか。
  bool shouldShowInterstitial({
    required GameMode mode,
    required AdCheckpoint checkpoint,
    required bool isEntitled,
  }) {
    if (isEntitled) return false;
    switch (mode) {
      case GameMode.timeAttack:
        // プレイ中は絶対に割り込まない。120 秒勝負の途中に全画面広告が
        // 挟まると、タイマーは止まらないのに操作だけ奪われる最悪の体験に
        // なる。許可するのはリザルト画面だけ。
        return checkpoint == AdCheckpoint.resultScreen;
      case GameMode.practice:
        // プラクティスにリザルト画面は無い。クリア直後のチェックポイント
        // だけが対象。
        if (checkpoint != AdCheckpoint.puzzleCleared) return false;
        return _clearsSinceLastAd >= clearsPerInterstitial;
    }
  }

  /// 広告を実際に表示できたら呼ぶ。次の 3 問区切りを再スタートする。
  ///
  /// 広告が読み込まれておらずスキップされた場合（[AdGateway] 側の話）は
  /// 呼ばないこと — 出せていないのにカウンタを消費すると、次に読み込みが
  /// 間に合ったとしても表示間隔がどんどん延びてしまう。
  void onInterstitialShown() {
    _clearsSinceLastAd = 0;
  }
}
