import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/bonus/bonus_grid.dart';
import '../domain/bonus_ticket.dart';

const String _prefsKey = 'make10.bonus';

/// ボーナスゲームのベストスコア・1 日 1 回の権利・中断した盤面を
/// 端末内に保存する。
///
/// [ChangeNotifier] を継承しているのは、ホーム画面の入口が 4 状態
/// （未解禁 / 解禁済み / 本日終了 / 中断あり）を切り替える必要があり、
/// タイムアタックのリザルトで解禁した瞬間にもホームへ戻る前に追従させたい
/// ため（既存 [EntitlementRepository] と同じパターン）。Riverpod の
/// FutureProvider はインスタンスを 1 度だけ生成してキャッシュするので、
/// その後のフィールドの書き換えはプロバイダの再評価では検知できない。
class BonusRepository extends ChangeNotifier {
  int _bestScore = 0;
  BonusTicket _ticket = BonusTicket();
  BonusGrid? _inProgressGrid;
  int _inProgressScore = 0;

  /// 直前の [_save] 呼び出しを表す。次の [_save] はこれへ鎖状につなぐ。
  ///
  /// [BonusSession.tap] は 1 手ごとに `saveProgress(...).ignore()` を
  /// await せず呼ぶ。`_save` には await が 2 箇所(`getInstance` と
  /// `setString`)あるので、これが無いと重なった呼び出しがストレージへ
  /// 発行される順序も完了する順序もばらばらになり得る。実機の
  /// プラットフォームチャネル越しの書き込みでは、後から発行した新しい
  /// 盤面より前に発行した古い盤面の方が先に確定してしまう(=古い盤面が
  /// 後から上書きして残る)ことがあり得るため、ここで直前の書き込みが
  /// 確定してから次を発行するようにする。
  Future<void> _writeQueue = Future<void>.value();

  int get bestScore => _bestScore;
  BonusTicket get ticket => _ticket;
  BonusGrid? get inProgressGrid => _inProgressGrid;
  int get inProgressScore => _inProgressScore;
  bool get hasInProgress => _inProgressGrid != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    var bestScore = 0;
    var ticket = BonusTicket();
    BonusGrid? grid;
    var score = 0;

    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        bestScore = data['bestScore'] as int? ?? 0;
        ticket = BonusTicket(
          unlockedOn: data['unlockedOn'] as String?,
          playedOn: data['playedOn'] as String?,
        );
        final inProgress = data['inProgress'];
        if (inProgress is Map<String, dynamic>) {
          // 途中状態だけが壊れている場合に、ベストスコアや権利まで
          // 巻き添えで失わないよう、ここは独立した try で囲む。
          try {
            grid = _decodeGrid(inProgress['grid']);
            score = inProgress['score'] as int? ?? 0;
          } catch (_) {
            grid = null;
            score = 0;
          }
        }
      } catch (_) {
        // 壊れていたら初期値で続行する。既存 StatsRepository.load と
        // 同じ方針で、プレイを妨げない。
        bestScore = 0;
        ticket = BonusTicket();
        grid = null;
        score = 0;
      }
    }

    _bestScore = bestScore;
    _ticket = ticket;
    _inProgressGrid = grid;
    _inProgressScore = score;
    notifyListeners();
  }

  /// 解禁条件を満たしたときに呼ぶ。新しく遊べるようになったら true。
  Future<bool> earn(String today) async {
    final unlocked = _ticket.earn(today);
    if (unlocked) {
      await _save();
      notifyListeners();
    }
    return unlocked;
  }

  /// ゲームを開始する。権利を消費し、初期盤面を途中状態として書く。
  ///
  /// 完了時ではなく開始時に消費するのが要点（仕様 §4.3）。強制終了で
  /// 無限にリトライできてしまうのを防ぐ。同時に盤面を保存することで、
  /// 中断しても再開できるようにして、開始時消費の実害を消している。
  Future<void> startGame(String today, BonusGrid grid) async {
    _ticket.consume(today);
    _inProgressGrid = grid;
    _inProgressScore = 0;
    await _save();
    notifyListeners();
  }

  Future<void> saveProgress(BonusGrid grid, int score) async {
    _inProgressGrid = grid;
    _inProgressScore = score;
    await _save();
    notifyListeners();
  }

  /// ゲームを終える。途中状態を消し、ベストを更新したら true。
  Future<bool> finish(int score) async {
    final improved = score > _bestScore;
    if (improved) _bestScore = score;
    _inProgressGrid = null;
    _inProgressScore = 0;
    await _save();
    notifyListeners();
    return improved;
  }

  /// [_writeQueue] へ鎖状につないでから書き込む。呼び出しごとに独立して
  /// 実行すると、重なった呼び出しがストレージへ発行される順序も完了する
  /// 順序もばらばらになり得る([_writeQueue] のコメント参照)。
  ///
  /// 直前の書き込みが失敗していても `catchError` で握りつぶしてから
  /// つなぐ。ここで握りつぶさずに前回の失敗をそのまま次へ渡すと、
  /// 失敗した Future が鎖に残り続け、それ以降の保存が全部巻き添えで
  /// 失敗するようになってしまう。この呼び出し自身の失敗は握りつぶさず、
  /// 返す [Future] を通じて呼び出し元(`saveProgress` など)にそのまま
  /// 伝える。
  Future<void> _save() {
    final scheduled = _writeQueue.catchError((_) {}).then((_) => _writeNow());
    _writeQueue = scheduled;
    return scheduled;
  }

  Future<void> _writeNow() async {
    final prefs = await SharedPreferences.getInstance();
    final grid = _inProgressGrid;
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'version': 1,
        'bestScore': _bestScore,
        'unlockedOn': _ticket.unlockedOn,
        'playedOn': _ticket.playedOn,
        if (grid != null)
          'inProgress': {
            'grid': grid.cells,
            'score': _inProgressScore,
          },
      }),
    );
  }
}

/// 保存された盤面を復元する。復元できない形なら例外を投げる
/// （呼び出し側が途中状態だけを破棄する）。
///
/// **`List<int>.from(...)` を使うのが要点。** `cast<int>()` は遅延評価
/// なので、int でない要素が混ざっていても [BonusRepository.load] の
/// try/catch をすり抜け、後から盤面を読んだ無関係な場所で TypeError
/// として現れる。この不具合はこのプロジェクトで実際に踏んだ。
///
/// **この防御は現状 `test/data/bonus_repository_test.dart` 単体では
/// 検出できない。** ここを `cast<int>()` に変えてもテストは全部通る
/// ——直後の長さチェックの `List.length` 呼び出し自体は cast を強制
/// 評価しないが、そのすぐ下の範囲チェックの `for (final v in cells)`
/// ループと、[BonusGrid.of] 内部の `List<int>.of(cells)` が、それぞれ
/// 独立に全要素を走査して cast を強制評価してしまうため。つまり今は
/// 3 箇所が同じ穴を偶然塞いでいる。`List<int>.from(...)` は、その 2 つが
/// 将来リファクタで無くなっても単独で穴を塞ぎ続ける、最後の防衛線として
/// 残す。
BonusGrid _decodeGrid(Object? raw) {
  if (raw is! List) throw const FormatException('grid が配列でない');
  final cells = List<int>.from(raw);
  if (cells.length != kBonusCells) {
    throw FormatException('grid の長さが $kBonusCells でない: ${cells.length}');
  }
  for (final v in cells) {
    if (v < 1 || v > kBonusTarget) {
      throw FormatException('grid に範囲外の値がある: $v');
    }
  }
  return BonusGrid.of(cells);
}
