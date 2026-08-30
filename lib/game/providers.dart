import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/history_repository.dart';
import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';

final historyRepositoryProvider = FutureProvider<HistoryRepository>((ref) async {
  final repo = HistoryRepository();
  await repo.load();
  return repo;
});

final statsRepositoryProvider = FutureProvider<StatsRepository>((ref) async {
  final repo = StatsRepository();
  await repo.load();
  return repo;
});

final puzzleRepositoryProvider = FutureProvider<PuzzleRepository>((ref) async {
  final history = await ref.watch(historyRepositoryProvider.future);
  final repo = PuzzleRepository(history);
  await repo.loadFromAsset();
  return repo;
});
