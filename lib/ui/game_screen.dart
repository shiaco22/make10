import 'package:flutter/material.dart';

import '../domain/difficulty.dart';
import '../domain/operation.dart';
import '../game/game_session.dart';
import 'widgets/action_bar.dart';
import 'widgets/board_view.dart';
import 'widgets/card_tile.dart';
import 'widgets/operator_bar.dart';
import 'widgets/responsive.dart';

/// 拒否メッセージを表示しておく「短時間」（仕様 §2.5 / §10）。
///
/// この間ユーザーが何もしなくても、[GameSession.dismissRejection] が
/// 呼ばれてメッセージが自動で消える。
const Duration kRejectionMessageDuration = Duration(seconds: 2);

/// タブレットで盤面に与える、カード自体の (拡大後の) 高さに対する上下の
/// 呼吸の余地 (電話換算値。実際に使うときは [uiScale] を掛ける)。
///
/// 0 にするとカードが直下の通知行にぴったりくっついて窮屈に見えるため
/// 少しだけ余白を持たせるが、この値を足しても演算子バーとの間隔は十分
/// 小さいまま収まる (test/ui/tablet_layout_test.dart で検証)。
const double _kTabletBoardBreathingRoom = 32;

/// 盤面を操作する画面。プラクティスとタイムアタックで共用する。
///
/// [statusRow] にはタイムアタックの残り時間などを差し込む。
class GameScreen extends StatefulWidget {
  final GameSession session;
  final Widget? statusRow;
  final VoidCallback? onExit;

  /// クリア直後の「次の問題へ」がタップされた時に、`session.nextPuzzle`の
  /// 代わりに呼ぶフック。省略時（null）は今日通り `session.nextPuzzle` を
  /// 直接呼ぶ。
  ///
  /// プラクティスの呼び出し側（HomeScreen）がここにインタースティシャル
  /// 広告のチェックを差し込む -- 「クリア!」の表示中ではなく、そこから
  /// 離れる操作そのものに広告の判断をひも付けるためのフック。答えを見た後
  /// の「次の問題へ」（下の `answerShown` 分岐）はこれを一切通らず、常に
  /// `session.nextPuzzle` を直接呼ぶ -- 答えを見た問題はそもそも
  /// 「クリア」ではないため。
  final VoidCallback? onAdvanceFromCleared;

  const GameScreen({
    super.key,
    required this.session,
    this.statusRow,
    this.onExit,
    this.onAdvanceFromCleared,
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

    final board = BoardView(
      cards: session.board.cards,
      selectedId: session.selectedCardId,
      highlightedIds: highlighted,
      onTapCard: session.tapCard,
      shakeCardId: session.lastRejectedCardId,
      shakeSignal: session.rejectionSeq,
    );

    // 電話 (scale == 1.0) では今日と全く同じ Expanded: Column は SafeArea
    // いっぱいに引き伸ばされ、盤面がその余りを丸ごと引き受ける。
    //
    // タブレットでは盤面を Flexible(loose) + 高さの上限に切り替える。
    // 上限は「拡大後のカード 1 枚分の高さ + 呼吸の余地」で、盤面は実際に
    // 必要な分より育たない -- Expanded のまま拡大率だけ上げると、背の
    // 高い画面の余白を盤面が全部引き受けてしまい、それこそが直そうとして
    // いる「盤面と演算子バーが遠く離れる」不具合そのものになる。
    // Flexible(loose) にしてあるので、万一この上限が画面の実際の余白より
    // 大きい場合 (縦の余裕が特に乏しい iPad mini 横向きなど) は Expanded
    // と同じように自動で縮み、はみ出さない。
    final scale = uiScale(context);
    final boardSlot = scale <= 1.0
        ? Expanded(child: board)
        : Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    (CardTile.baseHeight + _kTabletBoardBreathingRoom) *
                        scale,
              ),
              child: board,
            ),
          );

    // 電話では Column は今日どおり mainAxisSize.max (既定) のまま画面
    // いっぱいに広がる。タブレットでは mainAxisSize.min にしてこの Column
    // 自身の高さを「実際に必要な分だけ」へ縮め、下の Center で画面中央に
    // 置けるようにする -- 盤面・演算子バー・アクションバーが一塊のまま、
    // 余った縦の空間は塊の外 (Center が作る上下の余白) に出る。
    final content = Column(
      mainAxisSize: scale <= 1.0 ? MainAxisSize.max : MainAxisSize.min,
      children: [
        ?widget.statusRow,
        _pendingLine(theme),
        boardSlot,
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
    );

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
          // 電話では content (Column) をそのまま今日どおりに置く。タブ
          // レットだけ Center で包み、Column が mainAxisSize.min で縮めた
          // 実サイズを画面の中央へ置く。
          child: scale <= 1.0 ? content : Center(child: content),
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
            onPressed: widget.onAdvanceFromCleared ?? session.nextPuzzle,
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
