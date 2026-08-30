import 'package:flutter/foundation.dart';

import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';
import '../domain/board.dart';
import '../domain/difficulty.dart';
import '../domain/operation.dart';
import '../domain/puzzle.dart';
import '../domain/solver.dart';

enum PhaseKind { playing, cleared, answerShown }

/// 合成が拒否された理由。UI のメッセージ切り替えに使う。
enum RejectionKind { notDivisible, divideByZero }

/// プラクティス 1 セッションの進行。
///
/// タイムアタックはこれを内包して時間とスコアを足す（Task 12）。
class GameSession extends ChangeNotifier {
  final PuzzleRepository puzzles;
  final StatsRepository stats;
  final Difficulty difficulty;

  /// タイムアタックではヒントと答えを無効にする。
  final bool assistEnabled;

  /// プラクティス統計に記録するか。
  ///
  /// タイムアタックでは false。120 秒の勝負で解いた問題を
  /// プラクティスのクリア数や平均解答時間に混ぜると、統計の意味が壊れる
  /// （仕様 §8.2 は practice と timeAttack を別ブロックにしている）。
  final bool recordsPracticeStats;

  GameSession({
    required this.puzzles,
    required this.stats,
    required this.difficulty,
    this.assistEnabled = true,
    this.recordsPracticeStats = true,
  });

  late Puzzle _puzzle;
  late Board _board;
  PhaseKind _phase = PhaseKind.playing;
  int? _selectedCardId;
  Op? _selectedOp;
  RejectionKind? _lastRejection;
  SolverMove? _hintMove;
  bool _deadEndNotice = false;
  List<SolutionStep> _solutionSteps = const [];
  bool _usedHint = false;
  Stopwatch _stopwatch = Stopwatch();

  /// この配られた問題について、すでに統計へ結果
  /// （solved / answerShown / skipped のいずれか）を記録したか。
  ///
  /// undo や resetBoard でクリア後に playing へ戻れても、同じ問題を
  /// 再クリア・再スキップ・答え表示しても 2 回目以降は記録しない
  /// ようにするためのガード。_deal で新しい問題を配るたびにリセットする。
  bool _outcomeRecorded = false;

  Puzzle get puzzle => _puzzle;
  Board get board => _board;
  PhaseKind get phase => _phase;
  int? get selectedCardId => _selectedCardId;
  Op? get selectedOp => _selectedOp;
  RejectionKind? get lastRejection => _lastRejection;
  SolverMove? get hintMove => _hintMove;
  bool get deadEndNotice => _deadEndNotice;
  List<SolutionStep> get solutionSteps => _solutionSteps;

  /// 盤面が 1 枚になったが 10 ではない状態。UI が案内を出す。
  bool get missedTarget => _board.isFinished && !_board.isCleared;

  void start() {
    _deal(puzzles.next(difficulty));
  }

  /// テストで出題を固定するための入口。
  /// 並びを保つので、テストは渡した順にカードが並ぶと仮定してよい。
  @visibleForTesting
  void startWithDigits(List<int> digits) {
    _deal(
      Puzzle(
        digits: digits,
        solutionCount: solve(digits).length,
        requiresDivision: false,
        difficulty: difficulty,
      ),
      shuffle: false,
    );
  }

  void _deal(Puzzle puzzle, {bool shuffle = true}) {
    _puzzle = puzzle;
    final digits = List.of(puzzle.digits);
    if (shuffle) digits.shuffle();
    _board = Board.initial(digits);
    _phase = PhaseKind.playing;
    _selectedCardId = null;
    _selectedOp = null;
    _lastRejection = null;
    _hintMove = null;
    _deadEndNotice = false;
    _solutionSteps = const [];
    _usedHint = false;
    _outcomeRecorded = false;
    _stopwatch = Stopwatch()..start();
    notifyListeners();
  }

  /// 次の問題を配る。cleared / answerShown どちらのフェーズからも
  /// UI の「次へ」導線が直接呼ぶ、意図的に phase ガードを付けていない
  /// 進行専用の入口（skip はここを内部で使うが playing 限定でガードする）。
  void nextPuzzle() => _deal(puzzles.next(difficulty));

  void tapCard(int id) {
    if (_phase != PhaseKind.playing) return;
    _lastRejection = null;
    _hintMove = null;
    _deadEndNotice = false;

    if (_selectedCardId == null) {
      _selectedCardId = id;
      notifyListeners();
      return;
    }
    if (_selectedCardId == id) {
      _selectedCardId = null;
      _selectedOp = null;
      notifyListeners();
      return;
    }
    final op = _selectedOp;
    if (op == null) {
      // 演算子未選択で別のカードを押したら、選択を移す。
      _selectedCardId = id;
      notifyListeners();
      return;
    }

    final next = _board.apply(_selectedCardId!, id, op);
    if (next == null) {
      // 拒否時はカードと演算子の選択を維持する。
      final right = _board.cardById(id);
      _lastRejection = (right != null && right.value == 0 && op == Op.div)
          ? RejectionKind.divideByZero
          : RejectionKind.notDivisible;
      notifyListeners();
      return;
    }

    _board = next;
    _selectedCardId = null;
    _selectedOp = null;
    if (_board.isCleared) {
      _phase = PhaseKind.cleared;
      _stopwatch.stop();
      if (recordsPracticeStats && !_outcomeRecorded) {
        _outcomeRecorded = true;
        stats.recordSolved(
          difficulty,
          elapsedMs: _stopwatch.elapsedMilliseconds,
          usedHint: _usedHint,
        );
      }
    }
    notifyListeners();
  }

  void tapOp(Op op) {
    if (_phase != PhaseKind.playing) return;
    if (_selectedCardId == null) return;
    _selectedOp = op;
    _lastRejection = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedCardId = null;
    _selectedOp = null;
    _lastRejection = null;
    notifyListeners();
  }

  /// 選択・拒否理由・ヒント・詰み通知をまとめて破棄する。
  ///
  /// undo / resetBoard / showAnswer など、盤面や phase が変わって
  /// それまでの一時状態（特にヒント）が意味を失う場面で使う共通処理。
  /// 公開の [clearSelection] は「入力中の選択だけ止める」ためのもの
  /// なので、ヒントの破棄はそちらには混ぜない。
  void _clearTransientState() {
    _selectedCardId = null;
    _selectedOp = null;
    _lastRejection = null;
    _hintMove = null;
    _deadEndNotice = false;
  }

  void undo() {
    if (_phase == PhaseKind.answerShown) return;
    _board = _board.undo();
    _phase = PhaseKind.playing;
    _clearTransientState();
    notifyListeners();
  }

  void resetBoard() {
    if (_phase == PhaseKind.answerShown) return;
    _board = _board.reset();
    _phase = PhaseKind.playing;
    _clearTransientState();
    notifyListeners();
  }

  void requestHint() {
    if (!assistEnabled || _phase != PhaseKind.playing) return;
    _usedHint = true;
    final move = hint(_board.values);
    if (move == null) {
      _hintMove = null;
      _deadEndNotice = isDeadEnd(_board.values);
    } else {
      _hintMove = move;
      _deadEndNotice = false;
    }
    notifyListeners();
  }

  void showAnswer() {
    if (!assistEnabled || _phase != PhaseKind.playing) return;
    final solutions = solve(_puzzle.digits);
    _solutionSteps = solutions.isEmpty ? const [] : solutions.first.steps;
    _phase = PhaseKind.answerShown;
    _stopwatch.stop();
    _clearTransientState();
    if (recordsPracticeStats && !_outcomeRecorded) {
      _outcomeRecorded = true;
      stats.recordAnswerShown(difficulty);
    }
    notifyListeners();
  }

  void skip() {
    // 他のミューテータと同じく playing 中でなければ何もしない
    // （cleared/answerShown 後の「次へ」は nextPuzzle() の役目）。
    if (_phase != PhaseKind.playing) return;
    // undo でクリア後に playing へ戻れるため、phase ガードだけでは
    // 「クリア→undo→skip」で二重記録されるのを防げない。
    // スキップはタイムアタックでも使えるので、記録は明示的に切り分ける。
    if (recordsPracticeStats && !_outcomeRecorded) {
      _outcomeRecorded = true;
      stats.recordSkipped(difficulty);
    }
    nextPuzzle();
  }
}
