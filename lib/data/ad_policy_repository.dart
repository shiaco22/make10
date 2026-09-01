import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'make10.adPolicy.clearsSinceLastAd';

/// [AdPolicy]（`lib/domain/ad_policy.dart`）は自分では何も保存しない --
/// クラス doc の通り、[AdPolicy.clearsSinceLastAd] を再起動をまたいで
/// 覚えておくのは呼び出し側の仕事になっている。このクラスがその役目を担う。
///
/// 保存する値は「直近の広告表示から数えたプラクティスのクリア数」という
/// 単純な整数 1 個だけなので、[StatsRepository]/[HistoryRepository] のように
/// JSON にまとめる必要はなく、`shared_preferences` の int を直接使う。
class AdPolicyRepository {
  int _clearsSinceLastAd = 0;

  /// 起動時に [AdPolicy] の `initialClearsSinceLastAd` へそのまま渡す値。
  int get clearsSinceLastAd => _clearsSinceLastAd;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _clearsSinceLastAd = prefs.getInt(_prefsKey) ?? 0;
  }

  /// [AdPolicy.clearsSinceLastAd] が変化するたび（クリア記録時・広告表示時
  /// の両方）に呼び出し側が渡し直す想定。
  Future<void> save(int value) async {
    _clearsSinceLastAd = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
  }
}
