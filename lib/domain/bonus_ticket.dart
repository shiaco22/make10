/// ボーナスゲームが解禁されるまでに必要な、タイムアタック 1 回でのクリア数。
///
/// 難易度は問わない（easy / normal / hard のいずれでも 5 問）。無料で
/// 1 日 5 回まで貯まる報酬なので easy での稼ぎを害と見なさず、ルールが
/// 一行で説明できることを優先した（仕様 §4.1）。
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

/// 1 日に遊べるボーナスゲームの最大回数。
///
/// 回数は自動で配られない。タイムアタックで [kBonusUnlockClears] 問
/// クリアするたびに 1 回分たまり、ここで頭打ちになる。5 回遊ぶには
/// タイムアタックを 5 回勝つ必要がある（仕様 §1）。
const int kBonusPlaysPerDay = 5;

/// ボーナスゲームを今日あと何回遊べるかを数える、プラットフォーム非依存の
/// 純粋なロジック。盤面のルールを一切知らない。
///
/// 保存はしない（既存 `AdPolicy` と同じ考え方）。呼び出し側が [day] /
/// [earned] / [played] を読み出して永続化し、次回起動時にコンストラクタへ
/// 渡し直す。
///
/// **日付 2 つ（解禁した日・遊んだ日）ではなく、日付 1 つとカウンタ 2 つで
/// 持つ。** 日付では数が数えられないため、1 日 5 回にするには表現ごと
/// 変える必要があった（仕様 §2.1）。
class BonusTicket {
  String? _day;
  int _earned;
  int _played;

  /// [earned] は 0 以上 [kBonusPlaysPerDay] 以下、[played] は 0 以上
  /// [earned] 以下に丸める。壊れた保存データを読んでも、遊べる回数が
  /// **増える側ではなく減る側**に倒す（仕様 §6）。
  BonusTicket({String? day, int earned = 0, int played = 0})
      : _day = day, // ignore: prefer_initializing_formals
        _earned = earned.clamp(0, kBonusPlaysPerDay),
        _played = played.clamp(0, earned.clamp(0, kBonusPlaysPerDay));

  /// このカウンタが属するローカル日付。未設定なら null。
  String? get day => _day;

  /// [day] に獲得した回数。
  int get earned => _earned;

  /// [day] に開始した回数。
  int get played => _played;

  /// 今日あと何回遊べるか。日付が違えば 0。
  int playsLeft(String today) => _day == today ? _earned - _played : 0;

  /// 今日ボーナスゲームを遊べるか。
  bool isAvailable(String today) => playsLeft(today) > 0;

  /// タイムアタックで [kBonusUnlockClears] 問以上クリアしたときに呼ぶ。
  ///
  /// **返り値は「[earned] が増えたか」であって「遊べるようになったか」では
  /// ない。** 既に遊べる状態で 2 個目を獲得した場合も true になる。
  /// リザルトの告知はこの返り値で出すので、獲得のたびに true である
  /// 必要がある（仕様 §2.2）。
  bool earn(String today) {
    if (_day != today) {
      // 日付が変わったらカウンタごとリセットする。繰り越しはない。
      _day = today;
      _earned = 0;
      _played = 0;
    }
    if (_earned >= kBonusPlaysPerDay) return false;
    _earned++;
    return true;
  }

  /// ボーナスゲームを**開始した**ときに呼ぶ。
  ///
  /// 完了時ではなく開始時に消費する。完了時にすると、強制終了することで
  /// 無限にリトライできてしまう。中断で回数を失う実害は、途中の盤面を
  /// 永続化して再開できるようにすることで消している（仕様 §2.3）。
  ///
  /// 日付が違う場合と、獲得した分をすでに使い切っている場合は何もしない。
  /// [isAvailable] を通らずに呼ばれてもカウンタが壊れないようにするため。
  void consume(String today) {
    if (_day != today) return;
    if (_played >= _earned) return;
    _played++;
  }
}
