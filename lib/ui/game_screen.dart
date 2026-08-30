import 'package:flutter/material.dart';

import '../domain/difficulty.dart';
import '../domain/operation.dart';
import '../game/game_session.dart';
import 'widgets/action_bar.dart';
import 'widgets/board_view.dart';
import 'widgets/operator_bar.dart';

/// 盤面を操作する画面。プラクティスとタイムアタックで共用する。
///
/// [statusRow] にはタイムアタックの残り時間などを差し込む。
class GameScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
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
        leading: onExit == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: onExit,
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (statusRow != null) statusRow!,
              _pendingLine(theme),
              Expanded(
                child: BoardView(
                  cards: session.board.cards,
                  selectedId: session.selectedCardId,
                  highlightedIds: highlighted,
                  onTapCard: session.tapCard,
                ),
              ),
              _notice(theme),
              const SizedBox(height: 12),
              OperatorBar(
                selected: session.selectedOp,
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

    if (session.missedTarget) {
      return Text(
        '10 になりませんでした',
        style: TextStyle(color: scheme.error),
      );
    }

    return const SizedBox(height: 24);
  }
}
