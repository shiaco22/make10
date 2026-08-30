import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/time_attack_session.dart';
import 'game_screen.dart';
import 'result_screen.dart';

/// タイムアタックの画面。Ticker で実時間をセッションに流し込む。
class TimeAttackScreen extends StatefulWidget {
  final TimeAttackSession session;
  final VoidCallback onExit;

  /// 同じ難易度でもう一度始める。呼び出し側が新しいセッションを作る。
  /// 省略した場合も「もう一度」ボタンは表示され、onExit にフォールバックする。
  final VoidCallback? onRetry;

  const TimeAttackScreen({
    super.key,
    required this.session,
    required this.onExit,
    this.onRetry,
  });

  @override
  State<TimeAttackScreen> createState() => _TimeAttackScreenState();
}

class _TimeAttackScreenState extends State<TimeAttackScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _last;
    _last = elapsed;
    if (widget.session.isOver) {
      _ticker.stop();
      return;
    }
    widget.session.tick(delta);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        if (widget.session.isOver) {
          return ResultScreen(
            score: widget.session.score,
            bestScore: widget.session.stats
                .timeAttack(widget.session.difficulty)
                .bestScore,
            bestUpdated: widget.session.bestUpdated,
            isSaving: widget.session.isSavingResult,
            onRetry: widget.onRetry ?? widget.onExit,
            onHome: widget.onExit,
          );
        }
        return GameScreen(
          session: widget.session.session,
          onExit: widget.onExit,
          statusRow: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(widget.session.remaining),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'スコア ${widget.session.score}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}
