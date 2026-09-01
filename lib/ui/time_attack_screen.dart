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

  /// リザルト画面（スコア表示後）を「もう一度」「ホームへ」どちらで離れる
  /// 場合にも、実際に離れる直前に一度だけ呼ぶフック。省略時（null）は
  /// 何もせず、今日通り即座に進む。
  ///
  /// スコアは既に画面に表示された後、離れる操作そのものにだけ広告の判断を
  /// ひも付けることで、ご褒美であるスコア表示を広告が隠さないようにする
  /// （プラクティスの「クリア!」と「次の問題へ」の関係と同じ考え方 --
  /// GameScreen.onAdvanceFromCleared 参照）。プレイ中に閉じる「X」ボタン
  /// （GameScreen 側に渡す onExit）はここを一切通らない -- タイムアタックは
  /// プレイ中は絶対に広告を出さないため、リザルト画面固有のこのフックと
  /// 混ぜてはいけない。
  final Future<void> Function()? onLeavingResult;

  const TimeAttackScreen({
    super.key,
    required this.session,
    required this.onExit,
    this.onRetry,
    this.onLeavingResult,
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

  /// [widget.onLeavingResult] があれば待ってから [proceed] を呼ぶ。
  /// null なら (今日通り) 即座に同期的に [proceed] を呼ぶ -- フックを
  /// 渡さない既存の呼び出し元・テストの挙動を一切変えない。
  Future<void> _advanceFromResult(VoidCallback proceed) async {
    final hook = widget.onLeavingResult;
    if (hook != null) await hook();
    proceed();
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
            onRetry: () => _advanceFromResult(widget.onRetry ?? widget.onExit),
            onHome: () => _advanceFromResult(widget.onExit),
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
