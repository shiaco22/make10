import 'package:flutter/foundation.dart';

import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';
import '../domain/difficulty.dart';
import 'game_session.dart';

/// タイムアタックの制限時間。
const Duration kTimeAttackDuration = Duration(seconds: 120);

/// タイムアタック 1 回分。
///
/// 時計は [tick] で外から進める。実時間に依存させないことで、
/// 進行のテストが待ち時間なしに書ける。UI 側が Ticker から呼ぶ。
class TimeAttackSession extends ChangeNotifier {
  final GameSession session;
  final StatsRepository stats;
  final Difficulty difficulty;

  int _score = 0;
  Duration _elapsed = Duration.zero;
  bool _isOver = false;
  bool _bestUpdated = false;

  TimeAttackSession({
    required PuzzleRepository puzzles,
    required this.stats,
    required this.difficulty,
  }) : session = GameSession(
          puzzles: puzzles,
          stats: stats,
          difficulty: difficulty,
          assistEnabled: false,
          recordsPracticeStats: false,
        ) {
    session.addListener(_onSessionChanged);
  }

  int get score => _score;
  bool get isOver => _isOver;
  bool get bestUpdated => _bestUpdated;

  Duration get remaining {
    final left = kTimeAttackDuration - _elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void start() => session.start();

  void tick(Duration delta) {
    if (_isOver) return;
    _elapsed += delta;
    if (_elapsed >= kTimeAttackDuration) {
      _finish();
    }
    notifyListeners();
  }

  void _onSessionChanged() {
    if (_isOver) return;
    if (session.phase == PhaseKind.cleared) {
      _score++;
      // クリアした瞬間に次の問題を配る。リザルトは時間切れでのみ出す。
      session.nextPuzzle();
    }
    notifyListeners();
  }

  void _finish() {
    _isOver = true;
    // 解答中の問題はクリアしていないのでスコアに入らない。
    stats.recordTimeAttack(difficulty, _score).then((improved) {
      _bestUpdated = improved;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    session.dispose();
    super.dispose();
  }
}
