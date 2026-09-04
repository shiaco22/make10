import 'package:flutter/material.dart';

/// ボーナスゲームの結果。
///
/// [isSaving] の扱いは既存 [ResultScreen] と同じ。クリアした瞬間は
/// ベストスコアの書き込みが未完了で [bestUpdated] が false のままなので、
/// そのまま描くと古いベストが一瞬出てから「ベスト更新!」に切り替わる。
/// 保存中はこの行だけ伏せる。
class BonusResultScreen extends StatelessWidget {
  final int score;
  final int bestScore;
  final bool bestUpdated;
  final bool isSaving;

  /// 10 を作って終わったか。途中でやめた場合は false。
  final bool cleared;

  final VoidCallback onHome;

  const BonusResultScreen({
    super.key,
    required this.score,
    required this.bestScore,
    required this.bestUpdated,
    required this.isSaving,
    required this.cleared,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cleared ? '10 を作った!' : 'ここまで',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 24),
                Text(
                  'ボーナスゲームは 1 日 1 回。また明日、\n'
                  'タイムアタックで 5 問クリアすると遊べます。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                FilledButton(onPressed: onHome, child: const Text('ホームへ')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
