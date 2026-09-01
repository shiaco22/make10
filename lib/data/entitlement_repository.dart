import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/entitlement.dart';

const String _prefsKey = 'make10.entitlement';

/// 広告除去（月額購読 `make10_noads_monthly` / 買い切り `make10_noads_lifetime`）
/// の権利を端末内だけで読み書きする。
///
/// ## セキュリティ上の注意（意図的な設計判断であり見落としではない）
///
/// 購入の正当性は**サーバーへ問い合わせず**、端末に保存したこの
/// レコードだけで判定する。改造したクライアントは、このキーに
/// entitled な値を書き込むだけで広告を消せてしまう。
///
/// 月額 300 円・買い切り 980 円という価格帯では、レシート検証サーバー・
/// 鍵管理・リプレイ対策まで持つコストが割に合わない。「広告が消えるだけ」の
/// 機能なので、割られた場合の実害も限定的（他プレイヤーの得点やランキングに
/// 影響しない）。この非対称性を踏まえて、シンプルさを優先した —
/// 「サーバー検証はしない」という判断そのものを、ここに明文化しておく。
class EntitlementRepository {
  EntitlementState _state = EntitlementState.none;

  /// 現在保持している権利レコード（表示用）。判定には [isEntitled] を使うこと。
  EntitlementState get state => _state;

  /// [now] を省略すると実時刻で判定する（テストでは固定した時刻を渡せる）。
  bool isEntitled({DateTime? now}) => _state.isActiveOn(now ?? DateTime.now());

  Future<void> load() async {
    _state = EntitlementState.none;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _state = EntitlementState.fromJson(data);
    } catch (_) {
      // 壊れていたら「権利なし」として続行する。誤って広告を消したままに
      // するより、安全側（広告が出る側）に倒す。
      _state = EntitlementState.none;
    }
  }

  /// 買い切り `make10_noads_lifetime` の購入（新規または restore）を記録する。
  /// 失効しない — 一度きりで以後ずっと有効。
  Future<void> grantLifetime() async {
    _state = const EntitlementState(source: EntitlementSource.lifetime);
    await _save();
  }

  /// 月額購読 `make10_noads_monthly` が有効だとストアから確認できるたびに呼ぶ
  /// （新規購入時、および起動時の restorePurchases で再確認できたときの両方）。
  ///
  /// 既に買い切りを保持している場合は何もしない。買い切りは購読より
  /// 上位の権利であり、これを購読の情報で上書きすると、将来この
  /// 購読が失効した時点で買い切り購入者からも権利を奪ってしまう。
  Future<void> grantMonthly({DateTime? now}) async {
    if (_state.source == EntitlementSource.lifetime) return;
    _state = EntitlementState(
      source: EntitlementSource.monthly,
      expiresAt: (now ?? DateTime.now()).add(kSubscriptionTrustWindow),
    );
    await _save();
  }

  /// 権利を明示的に取り消す（例: 購入の払い戻しが判明した場合）。
  ///
  /// 購読の自然な失効は [EntitlementState.isActiveOn] が期限切れを見て
  /// 自動的に処理するため、通常はこれを呼ぶ必要はない。
  Future<void> revoke() async {
    _state = EntitlementState.none;
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{'version': 1, ..._state.toJson()};
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
