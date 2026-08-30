import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/difficulty.dart';

/// 難易度ごとに保持する出題履歴の上限。
const int kHistoryLimit = 50;

const String _prefsKey = 'make10.history';

/// 直近に出題した問題を難易度別に覚えておく。
///
/// プラクティスとタイムアタックで履歴を共有する（キーは難易度のみ）。
/// モードを切り替えた直後に同じ問題が出るのを避けるため。
class HistoryRepository {
  final Map<String, List<String>> _byDifficulty = {};

  Future<void> load() async {
    _byDifficulty.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final difficulty in Difficulty.values) {
        final list = decoded[difficulty.key];
        if (list is List) {
          _byDifficulty[difficulty.key] = list.cast<String>();
        }
      }
    } catch (_) {
      // 壊れていたら空履歴で続行する。重複が一時的に増えるだけ。
      _byDifficulty.clear();
    }
  }

  List<String> recent(Difficulty difficulty) =>
      List.unmodifiable(_byDifficulty[difficulty.key] ?? const <String>[]);

  Future<void> record(Difficulty difficulty, String puzzleKey) async {
    final list = _byDifficulty.putIfAbsent(difficulty.key, () => <String>[]);
    list.insert(0, puzzleKey);
    if (list.length > kHistoryLimit) {
      list.removeRange(kHistoryLimit, list.length);
    }
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{'version': 1};
    for (final difficulty in Difficulty.values) {
      payload[difficulty.key] = _byDifficulty[difficulty.key] ?? <String>[];
    }
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
