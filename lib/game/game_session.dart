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
  int? _lastRejectedCardId;

  /// 拒否のたびに単調増加する。値そのものに意味はなく、UI
  /// （[CardTile] の震えアニメーション）が「新しい拒否が起きた」ことを
  /// 検知するためだけに使う。同じカード・同じ理由の拒否が連続しても
  /// 必ず変化するので、震えを毎回再トリガーできる。
  int _rejectionSeq = 0;
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

  /// このセッションで配られた問題の数（1 始まり）。セッション内だけの
  /// カウントで、永続化はしない。プラクティスの問題番号表示（仕様
  /// §9.1）のために存在するが、_deal 自体は practice/timeAttack 共通の
  /// 経路なので、ここに置いても「配られた回数を数える」という素朴な
  /// 意味しか持たない。実際に画面へ出すかどうかは呼び出し側
  /// （HomeScreen）が決める — TimeAttackScreen は自前の statusRow
  /// （残り時間とスコア）を組むだけで、このカウンタを一切参照しない。
  int _puzzleNumber = 0;

  Puzzle get puzzle => _puzzle;
  Board get board => _board;
  PhaseKind get phase => _phase;
  int? get selectedCardId => _selectedCardId;
  Op? get selectedOp => _selectedOp;
  RejectionKind? get lastRejection => _lastRejection;

  /// 直近の拒否で、合成の相手として選ばれたカード（拒否の「対象カード」）
  /// の id。[lastRejection] と対で null/非 null が揃う。
  int? get lastRejectedCardId => _lastRejectedCardId;

  /// [lastRejection] のたびに単調増加する。詳細はフィールドのコメントを参照。
  int get rejectionSeq => _rejectionSeq;
  SolverMove? get hintMove => _hintMove;
  bool get deadEndNotice => _deadEndNotice;
  List<SolutionStep> get solutionSteps => _solutionSteps;

  /// 盤面が 1 枚になったが 10 ではない状態。UI が案内を出す。
  bool get missedTarget => _board.isFinished && !_board.isCleared;

  /// このセッションで何問目が配られているか（1 始まり）。
  int get puzzleNumber => _puzzleNumber;

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
    _puzzleNumber++;
    _puzzle = puzzle;
    final digits = List.of(puzzle.digits);
    if (shuffle) digits.shuffle();
    _board = Board.initial(digits);
    _phase = PhaseKind.playing;
    _selectedCardId = null;
    _selectedOp = null;
    _lastRejection = null;
    _lastRejectedCardId = null;
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

  /// アプリがフォアグラウンドを離れている間、計測を止める。
  ///
  /// _stopwatch は壁時計ベースなので、バックグラウンドで越夜されると
  /// 数時間分がそのまま経過時間として記録され、totalTimeMs /
  /// averageTimeMs を（消去手段が無いまま）永久に壊してしまう。呼び出し元
  /// （GameScreen）が WidgetsBindingObserver 経由でライフサイクルの変化を
  /// 中継する。既に止まっていれば Stopwatch.stop() は無害な no-op。
  void pauseTimer() {
    if (_phase == PhaseKind.playing) _stopwatch.stop();
  }

  /// [pauseTimer] で止めた計測を再開する。
  ///
  /// playing 以外（cleared / answerShown）で止まっている場合は、
  /// その問題の結果は既に確定・記録済みか、これ以上読まれない値なので
  /// 再開しない。Stopwatch.start() は経過時間をリセットしないので、
  /// バックグラウンドで過ぎた時間だけを除外して再開できる。
  void resumeTimer() {
    if (_phase == PhaseKind.playing) _stopwatch.start();
  }

  void tapCard(int id) {
    if (_phase != PhaseKind.playing) return;
    _lastRejection = null;
    _lastRejectedCardId = null;
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
      // 震えの対象は「組み合わせようとした相手カード」= 今回タップされた
      // id。_rejectionSeq は毎回必ず増やす。同じカードへの同じ理由の拒否が
      // 連続しても値が変わるようにするためで、CardTile はこの変化だけを
      // 見て震えを再生する（内容が同じでも「新しい拒否イベント」だと
      // 区別できないと、2 回目以降は何も起きなくなってしまう）。
      _lastRejectedCardId = id;
      _rejectionSeq++;
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
    _lastRejectedCardId = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedCardId = null;
    _selectedOp = null;
    _lastRejection = null;
    _lastRejectedCardId = null;
    notifyListeners();
  }

  /// 拒否メッセージ（と震えの対象カード）だけを消す。選択中のカードと
  /// 演算子には触れない — その維持は仕様上必須（§2.5）で、「短時間」表示の
  /// 自動消去がユーザーの選択まで壊してはいけない。
  ///
  /// 呼び出し時点で既に拒否理由が別経路（合成成功やヒントなど）で
  /// クリアされていれば何もしない。UI 側のタイマーは実時間で動くため、
  /// 発火した時点で状況が変わっている可能性を常に考慮する必要がある。
  void dismissRejection() {
    if (_lastRejection == null) return;
    _lastRejection = null;
    _lastRejectedCardId = null;
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
    _lastRejectedCardId = null;
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
    _lastRejection = null;
    _lastRejectedCardId = null;
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
