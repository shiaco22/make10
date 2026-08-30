import 'dart:io';
import 'dart:math';

import 'package:make10/data/history_repository.dart';
import 'package:make10/data/puzzle_repository.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/operation.dart';
import 'package:make10/domain/solver.dart';
import 'package:make10/game/game_session.dart';

String realPuzzlesJson() => File('assets/puzzles.json').readAsStringSync();

/// 指定した 4 枚で始まるセッションを作る。
///
/// リポジトリも読み込む。`skip` や `nextPuzzle` を呼ぶテストが
/// 未読み込みのプールに当たって落ちるのを防ぐため。
/// 並びはシャッフルされないので、テストは `cards[0]` が digits[0] だと仮定してよい。
Future<GameSession> sessionWithDigits(
  List<int> digits,
  StatsRepository stats,
) async {
  final history = HistoryRepository();
  await history.load();
  final puzzles = PuzzleRepository(history, random: Random(0));
  await puzzles.loadFromString(realPuzzlesJson());
  final session = GameSession(
    puzzles: puzzles,
    stats: stats,
    difficulty: Difficulty.normal,
  );
  session.startWithDigits(digits);
  return session;
}

/// 1 問だけクリアまで進める。
///
/// 1 問はちょうど 3 手なので 3 回で止める。`while (!isFinished)` にすると、
/// タイムアタックがクリア直後に次の問題を配るため永久に回り続ける。
void playSolution(GameSession session) {
  for (var i = 0; i < 3; i++) {
    final move = hint(session.board.values);
    if (move == null) return;
    final left = session.board.cards[move.leftIndex];
    final right = session.board.cards[move.rightIndex];
    session.tapCard(left.id);
    session.tapOp(move.op);
    session.tapCard(right.id);
  }
}
