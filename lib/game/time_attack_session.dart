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
  bool _isSavingResult = false;

  /// dispose 後の使用を防ぐガード。二重 dispose や、dispose 後に届く
  /// 非同期コールバック・ストレイな tick から notifyListeners を守る。
  bool _disposed = false;

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

  /// 結果の書き込みが確定するまで true。
  ///
  /// [_finish] が非同期の保存を開始した瞬間から、それが（成功・失敗を
  /// 問わず）完了するまでの間ずっと true になる。リザルト画面はこれを見て、
  /// ベスト更新表示が確定するまで古い値を出さずに待てる。
  bool get isSavingResult => _isSavingResult;

  Duration get remaining {
    final left = kTimeAttackDuration - _elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void start() => session.start();

  void tick(Duration delta) {
    // dispose 後に届くストレイな tick（Ticker の最後の 1 フレームなど）が
    // 自分の notifyListeners で落ちないよう、_isOver より先に見る。
    if (_disposed || _isOver) return;
    _elapsed += delta;
    if (_elapsed >= kTimeAttackDuration) {
      _finish();
    }
    notifyListeners();
  }

  void _onSessionChanged() {
    if (_disposed || _isOver) return;
    if (session.phase == PhaseKind.cleared) {
      _score++;
      // クリアした瞬間に次の問題を配る。リザルトは時間切れでのみ出す。
      session.nextPuzzle();
    }
    notifyListeners();
  }

  void _finish() {
    // isOver は tick() の呼び出し中に同期で確定させる。結果画面の遷移や
    // 入力ロックがこれを await 抜きで即座に見られる必要があるため、
    // ここより下の非同期の保存処理を待ってはいけない。
    _isOver = true;
    _isSavingResult = true;
    // 解答中の問題はクリアしていないのでスコアに入らない。
    stats.recordTimeAttack(difficulty, _score).then(
      (improved) {
        _isSavingResult = false;
        _bestUpdated = improved;
        // dispose() が保存の完了より先に走っていたら、ここで
        // notifyListeners を呼んではいけない（既に破棄済み）。
        if (_disposed) return;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        // 書き込みが失敗しても isSavingResult を true に固定したままにしない。
        _isSavingResult = false;
        if (_disposed) return;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    // 二重 dispose では内側の session.dispose() に届かせない。
    // ChangeNotifier.dispose() は再呼び出しでアサートするため、
    // 一度破棄済みなら即座に戻る。
    if (_disposed) return;
    _disposed = true;
    session.removeListener(_onSessionChanged);
    session.dispose();
    super.dispose();
  }
}
