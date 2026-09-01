/// 広告除去の権利をどちらの商品が与えているか。
enum EntitlementSource { none, monthly, lifetime }

/// [Difficulty] の `DifficultyDisplay.label` と同じ考え方 --
/// UI 表示名を列挙型のすぐそばに置く。[EntitlementSource.none] には
/// 呼ばない想定（呼び出し側は `isEntitled()` で権利があることを確認して
/// から使う）。
extension EntitlementSourceDisplay on EntitlementSource {
  String get label {
    switch (this) {
      case EntitlementSource.monthly:
        return '月額購読';
      case EntitlementSource.lifetime:
        return '買い切り';
      case EntitlementSource.none:
        return '';
    }
  }
}

/// サーバーが無い状態で「月額購読の権利をいつまで信用するか」の猶予期間。
///
/// [EntitlementRepository]（呼び出し側）は購入ストアから購読が有効だと
/// 確認できるたび（新規購入・起動時の restorePurchases 双方）、有効期限を
/// `確認できた時刻 + kSubscriptionTrustWindow` に更新する。レシートをサーバーで
/// 検証していないため、正確な次回更新日は取得できない — 30 日周期の
/// 購読に対して余裕を持たせた値にしてあり、アプリを起動してストアに再確認
/// できないまま丸ごと 1 周期以上が過ぎたら、ローカルの権利は自動的に失効した
/// ものとして扱う（fail-safe: 確認が取れない場合は「権利あり」より
/// 「権利なし」に倒す）。
const Duration kSubscriptionTrustWindow = Duration(days: 35);

/// 永続化する広告除去の権利。
///
/// [source] は表示用（「購読中」「買い切り購入済み」の出し分けなど）。
/// 実際に広告を消してよいかの判定は [isActiveOn] を使うこと — [source] が
/// `none` 以外というだけでは、期限切れの購読を見逃す。
class EntitlementState {
  final EntitlementSource source;

  /// 権利がいつまで有効か。
  ///
  /// [EntitlementSource.lifetime] と [EntitlementSource.none] では常に
  /// null（買い切りは失効しない／権利が無いので期限も無い）。
  /// [EntitlementSource.monthly] では非 null。
  final DateTime? expiresAt;

  const EntitlementState({this.source = EntitlementSource.none, this.expiresAt});

  static const EntitlementState none = EntitlementState();

  /// [now] の時点で広告を消してよいか。
  bool isActiveOn(DateTime now) {
    switch (source) {
      case EntitlementSource.none:
        return false;
      case EntitlementSource.lifetime:
        return true;
      case EntitlementSource.monthly:
        final expiry = expiresAt;
        return expiry != null && now.isBefore(expiry);
    }
  }

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  /// 形が壊れていれば（キー欠落・型違い・不明な source 名・不正な日時文字列）
  /// 例外を投げる。遅延評価される変換を挟まず、ここで即座に失敗させることで、
  /// 呼び出し側の try/catch が確実に捕まえられるようにする
  /// （`history_repository.dart` で `cast<String>()` の遅延評価が
  /// try/catch を素通りしてしまった教訓と同じ理由）。
  factory EntitlementState.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String;
    final source = EntitlementSource.values.byName(sourceName);
    final expiresAtRaw = json['expiresAt'] as String?;
    return EntitlementState(
      source: source,
      expiresAt: expiresAtRaw == null ? null : DateTime.parse(expiresAtRaw),
    );
  }
}
