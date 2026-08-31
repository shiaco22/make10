import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/history_repository.dart';
import 'package:make10/data/puzzle_repository.dart';
import 'package:make10/data/stats_repository.dart';
import 'package:make10/domain/difficulty.dart';
import 'package:make10/domain/solver.dart';
import 'package:make10/game/game_session.dart';
import 'package:make10/game/time_attack_session.dart';

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
    // 直前の合成結果は自動選択されている（GameSession.tapCard 末尾）。
    // それが今回の左オペランドと同じカードなら、ここで tapCard すると
    // 「選択済みカードの再タップ＝選択解除」に化けて手が一つ消える。
    // 既に選択済みならタップし直さず、選択を維持する。
    if (session.selectedCardId != left.id) {
      session.tapCard(left.id);
    }
    session.tapOp(move.op);
    session.tapCard(right.id);
  }
}

Future<TimeAttackSession> timeAttackWith(StatsRepository stats) async {
  final history = HistoryRepository();
  await history.load();
  final puzzles = PuzzleRepository(history, random: Random(3));
  await puzzles.loadFromString(realPuzzlesJson());
  final ta = TimeAttackSession(
    puzzles: puzzles,
    stats: stats,
    difficulty: Difficulty.normal,
  );
  ta.start();
  return ta;
}

/// [ta] の結果保存が確定するまでイベントループを回して待つ。
///
/// `TimeAttackSession._finish` は `StatsRepository.recordTimeAttack(...)` を
/// await せずに `.then(...)` で受けるだけなので、書き込みが実際に収まる
/// タイミングは呼び出し側からは非同期的にしか観測できない。
/// [TimeAttackSession.isSavingResult] は、その保存が（成功・失敗を問わず）
/// 確定するまで true のままになる、公開されている唯一の完了シグナルなので、
/// `await Future<void>.delayed(Duration.zero)` を 1 回叩いて祈るのではなく、
/// これが false に落ちるまで有界回数だけポーリングする。
///
/// [maxTurns] を使い切っても false に落ちなければ、無言で通さず
/// はっきりテストを失敗させる — 実装が壊れて保存が永久に確定しなくなった
/// ケースを、たまたま今のテストが黙って見逃すことがないように。
Future<void> waitForResultSave(TimeAttackSession ta, {int maxTurns = 50}) async {
  for (var i = 0; i < maxTurns && ta.isSavingResult; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  if (ta.isSavingResult) {
    fail(
      'TimeAttackSession.isSavingResult は $maxTurns 回イベントループを '
      '回しても true のままだった（結果の保存が確定しなかった）。',
    );
  }
}
