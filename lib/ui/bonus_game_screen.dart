import 'package:flutter/material.dart';

import '../game/bonus_session.dart';
import 'bonus_result_screen.dart';
import 'widgets/bonus_grid_view.dart';
import 'widgets/responsive.dart';

/// ボーナスゲームの画面。
///
/// 終了(クリア・途中終了のいずれも)したら [BonusResultScreen] に
/// 差し替える。既存 [TimeAttackScreen] と同じ形で、1 つのルートの中で
/// セッションの状態に応じて描き分ける。
class BonusGameScreen extends StatelessWidget {
  final BonusSession session;
  final VoidCallback onExit;

  const BonusGameScreen({
    super.key,
    required this.session,
    required this.onExit,
  });

  /// 途中でやめる確認。
  ///
  /// 権利はゲーム開始時に消費済みなので、ここでやめると今日はもう遊べない。
  /// 誤タップで 1 日 1 回の報酬を終わらせないよう、確認を挟む。
  Future<void> _confirmGiveUp(BuildContext context) async {
    final giveUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(
          'やめると今日のボーナスは終わりです。'
          'アプリを閉じるだけなら、次に開いたとき続きから遊べます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('やめる'),
          ),
        ],
      ),
    );
    if (giveUp ?? false) session.giveUp();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.isOver) {
          return BonusResultScreen(
            score: session.score,
            bestScore: session.bestScore,
            bestUpdated: session.bestUpdated,
            isSaving: session.isSavingResult,
            cleared: session.isCleared,
            onHome: onExit,
          );
        }

        final scale = uiScale(context);
        final theme = Theme.of(context);
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(12 * scale),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('スコア ${session.score}',
                          style: theme.textTheme.headlineSmall),
                      Text('最大 ${session.grid.maxValue}',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  // 高さを固定して、通知の出入りで盤面が動かないようにする。
                  SizedBox(
                    height: 20 * scale,
                    child: session.lastRepairedCells > 0
                        ? Text(
                            '打てる手が無くなったので'
                            '${session.lastRepairedCells} マス入れ替えました',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.primary),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // 盤面は残った領域いっぱいの正方形に収める。Expanded で
                  // 実際の余りを渡すことで、BonusGridView 側が短辺から
                  // 一辺を決められる(固定値を書かない)。
                  Expanded(
                    child: Center(
                      child: BonusGridView(
                        grid: session.grid,
                        onTapCell: session.tap,
                      ),
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  TextButton(
                    onPressed: () => _confirmGiveUp(context),
                    child: const Text('やめる'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
