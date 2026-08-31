import 'package:flutter/material.dart';

import '../domain/difficulty.dart';
import '../domain/operation.dart';
import '../game/game_session.dart';
import 'widgets/action_bar.dart';
import 'widgets/board_view.dart';
import 'widgets/operator_bar.dart';

/// 拒否メッセージを表示しておく「短時間」（仕様 §2.5 / §10）。
///
/// この間ユーザーが何もしなくても、[GameSession.dismissRejection] が
/// 呼ばれてメッセージが自動で消える。
const Duration kRejectionMessageDuration = Duration(seconds: 2);

/// 盤面を操作する画面。プラクティスとタイムアタックで共用する。
///
/// [statusRow] にはタイムアタックの残り時間などを差し込む。
class GameScreen extends StatefulWidget {
  final GameSession session;
  final Widget? statusRow;
  final VoidCallback? onExit;

  const GameScreen({
    super.key,
    required this.session,
    this.statusRow,
    this.onExit,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// アプリがフォアグラウンドに無い間は [GameSession] の計測用ストップウォッチを
/// 止める（WidgetsBindingObserver 自体は GameScreen に付ける。ChangeNotifier
/// である GameSession は「画面にマウントされている」区間を自分だけでは
/// 知り得ず、特にプラクティスのセッションは今のところ誰も dispose を呼ばない
/// ので、生成時に addObserver すると外す機会がないまま溜まってしまう。
/// StatefulWidget の State なら initState/dispose のペアで確実に対になる）。
///
/// タイムアタック中の GameScreen（TimeAttackScreen が内包する GameSession）
/// にもこの observer は付くが、その GameSession は recordsPracticeStats が
/// false で Stopwatch の値を誰も読まないため、止めても挙動は変わらない。
/// タイムアタックの残り時間は TimeAttackSession が Ticker から受け取る
/// 実時間のみで決まり、これは意図的に変えない
/// （バックグラウンドから戻ると一気に時間切れになるのは許容する仕様）。
class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// 「短時間」表示を計るアニメーション。dart:async の Timer は使わない
  /// — GameSession は Timer を持たずに済み、単体テストは Timer 完走を
  /// 待つ必要がない。Ticker ベースなので widget テストは
  /// tester.pump(duration) でそのまま時間を進められる。
  late final AnimationController _rejectionMessageController;

  /// 直近に「短時間」表示タイマーを張り直した拒否の rejectionSeq。
  /// 同じ拒否に対して forward(from: 0) を重ねて呼ばないためのガード。
  int _handledRejectionSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rejectionMessageController = AnimationController(
      vsync: this,
      duration: kRejectionMessageDuration,
    )..addStatusListener(_onRejectionMessageStatusChanged);
    widget.session.addListener(_syncRejectionAutoDismiss);
    _syncRejectionAutoDismiss();
  }

  @override
  void dispose() {
    widget.session.removeListener(_syncRejectionAutoDismiss);
    _rejectionMessageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.resumeTimer();
    } else {
      widget.session.pauseTimer();
    }
  }

  void _onRejectionMessageStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // 選択中のカード・演算子は維持したまま、メッセージだけを消す
      // （仕様 §2.5: 拒否後もユーザーは B を選び直すだけでよい）。
      widget.session.dismissRejection();
    }
  }

  /// 新しい拒否が起きるたびに「短時間」タイマーを最初からやり直す。
  /// 拒否が（合成成功やヒントなど）他の経路で先に消えていれば止める。
  ///
  /// GameSession.rejectionSeq は拒否のたびに単調増加するので、同じ
  /// カード・同じ理由の拒否が連続しても新しいタイマーとして扱える。
  void _syncRejectionAutoDismiss() {
    final session = widget.session;
    if (session.lastRejection == null) {
      _rejectionMessageController.stop();
      return;
    }
    if (session.rejectionSeq == _handledRejectionSeq) return;
    _handledRejectionSeq = session.rejectionSeq;
    _rejectionMessageController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final highlighted = <int>{};
    final move = session.hintMove;
    if (move != null) {
      highlighted.add(session.board.cards[move.leftIndex].id);
      highlighted.add(session.board.cards[move.rightIndex].id);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.difficulty.label),
        leading: widget.onExit == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onExit,
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ?widget.statusRow,
              _pendingLine(theme),
              Expanded(
                child: BoardView(
                  cards: session.board.cards,
                  selectedId: session.selectedCardId,
                  highlightedIds: highlighted,
                  onTapCard: session.tapCard,
                  shakeCardId: session.lastRejectedCardId,
                  shakeSignal: session.rejectionSeq,
                ),
              ),
              _notice(theme),
              const SizedBox(height: 12),
              OperatorBar(
                selected: session.selectedOp,
                hintedOp: session.hintFormula?.op,
                onTap: session.tapOp,
              ),
              const SizedBox(height: 12),
              ActionBar(
                canUndo: session.board.canUndo,
                interactionEnabled: session.phase == PhaseKind.playing,
                assistEnabled: session.assistEnabled &&
                    session.phase == PhaseKind.playing,
                onUndo: session.undo,
                onReset: session.resetBoard,
                onHint: session.requestHint,
                onAnswer: session.showAnswer,
                onSkip: session.skip,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `7 ÷ ?` のように、いま組み立て中の式を見せる。
  Widget _pendingLine(ThemeData theme) {
    final session = widget.session;
    final id = session.selectedCardId;
    if (id == null) return const SizedBox(height: 32);
    final card = session.board.cardById(id);
    if (card == null) return const SizedBox(height: 32);
    final op = session.selectedOp;
    final text = op == null ? '${card.value}' : '${card.value} ${opSymbol(op)} ?';
    return SizedBox(
      height: 32,
      child: Center(
        child: Text(text, style: theme.textTheme.titleLarge),
      ),
    );
  }

  Widget _notice(ThemeData theme) {
    final session = widget.session;
    final scheme = theme.colorScheme;

    if (session.phase == PhaseKind.answerShown) {
      return Column(
        children: [
          for (final step in session.solutionSteps) Text(step.toString()),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: session.nextPuzzle,
            child: const Text('次の問題へ'),
          ),
        ],
      );
    }

    if (session.phase == PhaseKind.cleared) {
      return Column(
        children: [
          Text('クリア!', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: session.nextPuzzle,
            child: const Text('次の問題へ'),
          ),
        ],
      );
    }

    final rejection = session.lastRejection;
    if (rejection != null) {
      final message = rejection == RejectionKind.divideByZero
          ? '0 では割れません'
          : '割り切れません';
      return Text(message, style: TextStyle(color: scheme.error));
    }

    if (session.deadEndNotice) {
      return Text(
        'この手順からは 10 を作れません。戻しましょう',
        style: TextStyle(color: scheme.error),
        textAlign: TextAlign.center,
      );
    }

    // ヒントの 2 回目以降の押下: ハイライトに加えて、その 1 手だけを式で
    // 見せる（答えの全 3 手とは違い、次の一手だけ）。書式は答えの各手
    // (SolutionStep.toString()) と揃える。
    final hintFormula = session.hintFormula;
    if (hintFormula != null) {
      return Text(hintFormula.toString());
    }

    if (session.missedTarget) {
      return Text(
        '10 になりませんでした',
        style: TextStyle(color: scheme.error),
      );
    }

    return const SizedBox(height: 24);
  }
}
