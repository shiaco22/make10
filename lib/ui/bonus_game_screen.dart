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
class BonusGameScreen extends StatefulWidget {
  final BonusSession session;
  final VoidCallback onExit;

  const BonusGameScreen({
    super.key,
    required this.session,
    required this.onExit,
  });

  @override
  State<BonusGameScreen> createState() => _BonusGameScreenState();
}

class _BonusGameScreenState extends State<BonusGameScreen> {
  /// ゲームオーバーの重ね表示を見終えて、結果画面へ進むことを選んだか。
  ///
  /// ゲームオーバーで即座に結果画面へ飛ばすと、なぜ負けたのかが見えない。
  /// 修復はこれまで一瞬で自動的に行われてきたので、プレイヤーは自分を
  /// 詰ませた盤面を一度見て初めて因果を理解できる(仕様 §3.2)。クリアと
  /// 「やめる」はプレイヤー自身の行為なので、この段は挟まず今までどおり
  /// 直接結果画面へ進む。
  bool _gameOverAcknowledged = false;

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
    if (giveUp ?? false) widget.session.giveUp();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        // isGameOver は isOver を含意するので、素朴に「isOver なら結果画面」
        // にすると重ね表示へ絶対に到達できなくなる。重ね表示を見終えた
        // (_gameOverAcknowledged)、またはそもそもゲームオーバー以外の
        // 終わり方(クリア・やめた)のときだけ結果画面へ進む。
        final showResult =
            session.isOver && (!session.isGameOver || _gameOverAcknowledged);
        if (showResult) {
          return BonusResultScreen(
            score: session.score,
            bestScore: session.bestScore,
            bestUpdated: session.bestUpdated,
            isSaving: session.isSavingResult,
            // showResult が真の分岐に入るのは isOver が真のときだけなので
            // outcome は非 null。
            outcome: session.outcome!,
            onHome: widget.onExit,
          );
        }

        // ゲームオーバーの重ね表示を出している間(この Scaffold 分岐に
        // 入っているのに isGameOver な間)は、終わったゲームに対して
        // 操作できてはいけない。盤面のタップは session.tap 自身が isOver
        // を見て無視するのに加え、重ね表示の不透明な Container がタップを
        // 物理的に奪う。やめるボタンは重ね表示の外(盤面の Stack の外)に
        // あるので、そちらは別途ここで塞ぐ。
        final showingGameOverOverlay = session.isGameOver;

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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('最大 ${session.grid.maxValue}',
                              style: theme.textTheme.bodyMedium),
                          SizedBox(width: 8 * scale),
                          // 入れ替えは有限資源になったので常時出す。残りが
                          // 見えないと「なぜ負けたか」も「あと何回耐えられ
                          // るか」も分からない(仕様 §3.3)。
                          //
                          // titleMedium ではなく bodyMedium にしてあるのは、
                          // 320pt 幅でこの行が 3 項目(スコア・最大・入れ替え)
                          // になったことで、titleMedium のままだと実測で
                          // RenderFlex が右へ 14px 溢れたため
                          // (test/ui/bonus_game_screen_test.dart の
                          // '320pt 幅で溢れない' が実際に検出した)。
                          Text(
                            '入れ替え ${session.repairsLeft}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: session.repairsLeft <= 3
                                  ? theme.colorScheme.error
                                  : null,
                              fontWeight: session.repairsLeft <= 3
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // 高さを固定して、通知の出入りで盤面が動かないようにする。
                  SizedBox(
                    height: 20 * scale,
                    child: session.repairsLeft == 0
                        ? Text(
                            '入れ替えを使い切りました。次に詰んだら終わりです',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          )
                        : session.lastRepairedCells > 0
                            ? Text(
                                '打てる手が無くなったので'
                                '${session.lastRepairedCells} マス入れ替えました',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary),
                              )
                            : const SizedBox.shrink(),
                  ),
                  // 盤面は残った領域いっぱいの正方形に収める。Expanded で
                  // 実際の余りを渡すことで、BonusGridView 側が短辺から
                  // 一辺を決められる(固定値を書かない)。
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: BonusGridView(
                            grid: session.grid,
                            onTapCell: session.tap,
                            lastMerge: session.lastMerge,
                            moveSerial: session.moveCount,
                          ),
                        ),
                        if (session.isGameOver)
                          _GameOverOverlay(
                            score: session.score,
                            onResult: () =>
                                setState(() => _gameOverAcknowledged = true),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  TextButton(
                    onPressed: showingGameOverOverlay
                        ? null
                        : () => _confirmGiveUp(context),
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

/// 盤面の上に重ねるゲームオーバーの表示。
///
/// 盤面を隠さずに重ねるのが要点(仕様 §3.2) -- 自分を詰ませた盤面が
/// 見えていることが、この表示の目的そのものになる。
class _GameOverOverlay extends StatelessWidget {
  final int score;
  final VoidCallback onResult;

  const _GameOverOverlay({required this.score, required this.onResult});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      // 盤面を隠しきらない程度に落とす。自分を詰ませた盤面が見えている
      // ことが、この表示の目的そのものなので不透明にはしない。
      color: theme.colorScheme.surface.withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ゲームオーバー', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('打つ手がありません', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text('スコア $score', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          FilledButton(onPressed: onResult, child: const Text('結果へ')),
        ],
      ),
    );
  }
}
