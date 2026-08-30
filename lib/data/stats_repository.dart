import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/difficulty.dart';
import 'models/stats.dart';

const String _prefsKey = 'make10.stats';

class StatsRepository {
  final Map<String, PracticeStats> _practice = {};
  final Map<String, TimeAttackStats> _timeAttack = {};

  Future<void> load() async {
    _practice.clear();
    _timeAttack.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final practice = data['practice'] as Map<String, dynamic>? ?? {};
      final timeAttack = data['timeAttack'] as Map<String, dynamic>? ?? {};
      for (final difficulty in Difficulty.values) {
        final p = practice[difficulty.key];
        if (p is Map<String, dynamic>) {
          _practice[difficulty.key] = PracticeStats.fromJson(p);
        }
        final t = timeAttack[difficulty.key];
        if (t is Map<String, dynamic>) {
          _timeAttack[difficulty.key] = TimeAttackStats.fromJson(t);
        }
      }
    } catch (_) {
      // 壊れていたら初期値で続行する。プレイを妨げない。
      _practice.clear();
      _timeAttack.clear();
    }
  }

  PracticeStats practice(Difficulty d) =>
      _practice[d.key] ?? const PracticeStats();

  TimeAttackStats timeAttack(Difficulty d) =>
      _timeAttack[d.key] ?? const TimeAttackStats();

  Future<void> recordSolved(
    Difficulty d, {
    required int elapsedMs,
    required bool usedHint,
  }) async {
    final current = practice(d);
    _practice[d.key] = current.copyWith(
      solved: current.solved + 1,
      totalTimeMs: current.totalTimeMs + elapsedMs,
      hintUsed: current.hintUsed + (usedHint ? 1 : 0),
    );
    await _save();
  }

  Future<void> recordAnswerShown(Difficulty d) async {
    final current = practice(d);
    _practice[d.key] = current.copyWith(answerShown: current.answerShown + 1);
    await _save();
  }

  Future<void> recordSkipped(Difficulty d) async {
    final current = practice(d);
    _practice[d.key] = current.copyWith(skipped: current.skipped + 1);
    await _save();
  }

  /// スコアを記録し、ベスト更新なら true を返す。
  Future<bool> recordTimeAttack(Difficulty d, int score) async {
    final current = timeAttack(d);
    final improved = score > current.bestScore;
    _timeAttack[d.key] = TimeAttackStats(
      bestScore: improved ? score : current.bestScore,
      playCount: current.playCount + 1,
    );
    await _save();
    return improved;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'version': 1,
      'practice': {
        for (final d in Difficulty.values) d.key: practice(d).toJson(),
      },
      'timeAttack': {
        for (final d in Difficulty.values) d.key: timeAttack(d).toJson(),
      },
    };
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
