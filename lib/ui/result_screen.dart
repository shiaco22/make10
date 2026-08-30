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

  const ResultScreen({
    super.key,
    required this.score,
    required this.bestScore,
    required this.bestUpdated,
    required this.isSaving,
    required this.onRetry,
    required this.onHome,
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
