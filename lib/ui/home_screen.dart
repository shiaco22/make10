import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';
import '../domain/difficulty.dart';
import '../game/game_session.dart';
import '../game/providers.dart';
import '../game/time_attack_session.dart';
import 'difficulty_screen.dart';
import 'game_screen.dart';
import 'stats_screen.dart';
import 'time_attack_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<Difficulty?> _pickDifficulty(
    BuildContext context,
    String title,
  ) {
    return Navigator.of(context).push<Difficulty>(
      MaterialPageRoute(
        builder: (context) => DifficultyScreen(
          title: title,
          onSelected: (d) => Navigator.of(context).pop(d),
        ),
      ),
    );
  }

  void _startPractice(
    BuildContext context,
    PuzzleRepository puzzles,
    StatsRepository stats,
    Difficulty difficulty,
  ) {
    final session = GameSession(
      puzzles: puzzles,
      stats: stats,
      difficulty: difficulty,
    )..start();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GameScreen(
          session: session,
          onExit: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// 同じ難易度で 1 回分を開始する。
  ///
  /// 「もう一度」は今の画面を閉じてから同じ難易度で開き直す。
  /// TimeAttackSession は使い捨てなので、作り直すのが最も素直。
  void _startTimeAttack(
    BuildContext context,
    PuzzleRepository puzzles,
    StatsRepository stats,
    Difficulty difficulty,
  ) {
    final session = TimeAttackSession(
      puzzles: puzzles,
      stats: stats,
      difficulty: difficulty,
    )..start();
    final navigator = Navigator.of(context);
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (routeContext) => TimeAttackScreen(
              session: session,
              onExit: () => Navigator.of(routeContext).pop(),
              onRetry: () {
                Navigator.of(routeContext).pop();
                _startTimeAttack(context, puzzles, stats, difficulty);
              },
            ),
          ),
        )
        .then((_) => session.dispose());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzlesAsync = ref.watch(puzzleRepositoryProvider);
    final statsAsync = ref.watch(statsRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: puzzlesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('問題データを読み込めませんでした\n$e',
                  textAlign: TextAlign.center),
            ),
          ),
          data: (puzzles) => statsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (stats) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MAKE 10',
                      style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 240,
                    height: 56,
                    child: FilledButton(
                      onPressed: () async {
                        final d =
                            await _pickDifficulty(context, 'プラクティス');
                        if (d != null && context.mounted) {
                          _startPractice(context, puzzles, stats, d);
                        }
                      },
                      child: const Text('プラクティス'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 240,
                    height: 56,
                    child: FilledButton(
                      onPressed: () async {
                        final d =
                            await _pickDifficulty(context, 'タイムアタック');
                        if (d != null && context.mounted) {
                          _startTimeAttack(context, puzzles, stats, d);
                        }
                      },
                      child: const Text('タイムアタック'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => StatsScreen(stats: stats),
                      ),
                    ),
                    child: const Text('統計'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
