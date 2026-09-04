import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  final int score;
  final int bestScore;
  final bool bestUpdated;

  /// ベストスコアの保存がまだ終わっていないか。
  ///
  /// 時間切れの瞬間は書き込みが未完了で bestUpdated が false のままなので、
  /// そのまま描くと古いベストが一瞬出てから「ベスト更新!」に切り替わる。
  /// 保存中はこの行だけ伏せて、ちらつきを防ぐ。
  final bool isSaving;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  /// スコアの下に差し込む告知。省略時（null）は何も描かず、今日通りの
  /// 表示になる。
  ///
  /// ボーナスゲームの解禁をここに出す。リザルトは既にスコアを見せ終えた
  /// 場所なので、次に何ができるようになったかを伝えるのに適している。
  final Widget? notice;

  const ResultScreen({
    super.key,
    required this.score,
    required this.bestScore,
    required this.bestUpdated,
    required this.isSaving,
    required this.onRetry,
    required this.onHome,
    this.notice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('スコア $score', style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              // 高さを固定して、保存完了時に下のボタンが動かないようにする。
              SizedBox(
                height: 24,
                child: isSaving
                    ? const SizedBox.shrink()
                    : bestUpdated
                        ? Text(
                            'ベスト更新!',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: theme.colorScheme.primary),
                          )
                        : Text('ベスト $bestScore',
                            style: theme.textTheme.titleMedium),
              ),
              if (notice != null) ...[
                const SizedBox(height: 16),
                notice!,
              ],
              const SizedBox(height: 32),
              FilledButton(onPressed: onRetry, child: const Text('もう一度')),
              const SizedBox(height: 8),
              TextButton(onPressed: onHome, child: const Text('ホームへ')),
            ],
          ),
        ),
      ),
    );
  }
}
