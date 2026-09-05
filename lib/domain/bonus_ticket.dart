/// ボーナスゲームが解禁されるまでに必要な、タイムアタック 1 回でのクリア数。
///
/// 難易度は問わない（easy / normal / hard のいずれでも 5 問）。無料の
/// 1 日 1 回の報酬なので easy での稼ぎを害と見なさず、ルールが一行で
/// 説明できることを優先した（仕様 §4.1）。
const int kBonusUnlockClears = 5;

/// ローカル日付を `yyyy-MM-dd` に整形する。
///
/// 権利の管理に整数の秒やミリ秒を使わないのが要点。サマータイムや端末の
/// 時刻変更で日付境界の判定が壊れるため、初めから「日」を単位にする
/// （仕様 §4.2）。
String bonusDateKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

/// ボーナスゲームを「今日まだ遊べるか」だけを判定する、プラットフォーム
/// 非依存の純粋なロジック。盤面のルールを一切知らない。
///
/// 保存はしない（既存 `AdPolicy` と同じ考え方）。呼び出し側が
/// [unlockedOn] / [playedOn] を読み出して永続化し、次回起動時に
/// コンストラクタへ渡し直す。
class BonusTicket {
  String? _unlockedOn;
  String? _playedOn;

  // `this._unlockedOn` / `this._playedOn` の initializing formal は使わない
  // — そのまま使うと外から渡す名前付き引数がフィールド名の
  // `_unlockedOn` / `_playedOn` になり、private な内部表現が公開 API に
  // 漏れる。読み出しは public な getter に限定したいので、ここは
  // 手動代入のままにする。
  BonusTicket({String? unlockedOn, String? playedOn})
      : _unlockedOn = unlockedOn, // ignore: prefer_initializing_formals
        _playedOn = playedOn; // ignore: prefer_initializing_formals

  /// 最後に解禁条件を満たした日。
  String? get unlockedOn => _unlockedOn;

  /// 最後にボーナスゲームを開始した日。
  String? get playedOn => _playedOn;

  /// 解禁条件を満たしたときに呼ぶ。**新しく遊べるようになったら** true。
  ///
  /// その日すでに遊んでいれば何もしない。ここで解禁し直せてしまうと、
  /// 「タイムアタックで 5 問クリア → ボーナス → また 5 問クリア」で
  /// 1 日に何度でも遊べてしまう。
  bool earn(String today) {
    if (_playedOn == today) return false;
    if (_unlockedOn == today) return false;
    _unlockedOn = today;
    return true;
  }

  /// 今日ボーナスゲームを遊べるか。
  ///
  /// 権利は繰り越さない。前日に解禁して遊ばなかった場合、翌日には
  /// `_unlockedOn != today` になって消える（仕様 §4.2）。
  bool isAvailable(String today) =>
      _unlockedOn == today && _playedOn != today;

  /// ボーナスゲームを**開始した**ときに呼ぶ。
  ///
  /// 完了時ではなく開始時に消費する。完了時にすると、強制終了することで
  /// 無限にリトライできてしまう（仕様 §4.3）。中断で権利を失う実害は、
  /// 途中の盤面を永続化して再開できるようにすることで消している。
  void consume(String today) {
    _playedOn = today;
  }
}
