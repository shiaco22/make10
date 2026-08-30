import 'package:flutter/material.dart';

import '../data/stats_repository.dart';
import '../domain/difficulty.dart';

class StatsScreen extends StatelessWidget {
  final StatsRepository stats;

  const StatsScreen({super.key, required this.stats});

  String _average(int? ms) {
    if (ms == null) return '-';
    return '${(ms / 1000).toStringAsFixed(1)} 秒';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('統計')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final difficulty in Difficulty.values)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(difficulty.label, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('クリア ${stats.practice(difficulty).solved} 問'),
                    Text('平均 ${_average(
                      stats.practice(difficulty).averageTimeMs,
                    )}'),
                    Text('ヒント ${stats.practice(difficulty).hintUsed} 回'),
                    Text('答え ${stats.practice(difficulty).answerShown} 回'),
                    Text('スキップ ${stats.practice(difficulty).skipped} 回'),
                    const Divider(),
                    Text('タイムアタック ベスト '
                        '${stats.timeAttack(difficulty).bestScore} 問'),
                    Text('プレイ ${stats.timeAttack(difficulty).playCount} 回'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
