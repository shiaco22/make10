import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/bonus_repository.dart';
import '../domain/bonus/bonus_grid.dart';

/// ボーナスゲーム 1 回の終わり方。
///
/// bool 2 つ(クリアしたか・やめたか)では 3 状態を表せなくなったので
/// 列挙にした。結果画面の見出しはこれで分岐する(仕様 §3.2)。
enum BonusOutcome {
  /// 10 を作った。
  cleared,

  /// 入れ替えを使い切った状態で詰んだ。
  gameOver,

  /// プレイヤーが自分でやめた。
  gaveUp,
}

/// ボーナスゲーム 1 回分。
///
/// 盤面のルールは [BonusGrid](純粋・イミュータブル)にあり、ここは
/// 乱数・スコアの累積・永続化をつなぐだけに留める。
///
/// [TimeAttackSession] と同じ `_disposed` ガードを持つ。あちらでは
/// ガードが無いために 3 つのクラッシュ経路があった(dispose 後に届く
/// 非同期の保存完了、二重 dispose、破棄後のストレイなイベント)。
/// ここも結果の保存が非同期なので同じ形が必要になる。
class BonusSession extends ChangeNotifier {
  final BonusRepository repository;
  final Random _random;

  BonusGrid _grid;
  int _score;
  BonusOutcome? _outcome;
  int _repairsUsed;
  int _lastRepairedCells = 0;
  BonusMerge? _lastMerge;
  int _moveCount = 0;
  bool _isSavingResult = false;
  bool _bestUpdated = false;
  bool _disposed = false;

  /// [grid] と [score] は新規なら `BonusGrid.deal(...)` と 0、再開なら
  /// [BonusRepository] に保存されていた値を渡す。
  ///
  /// [repairsUsed] は再開時に、保存されていた使用済みの回数を渡す。
  /// 渡さないと中断・再開のたびに入れ替えが上限まで戻り、上限が
  /// 事実上無くなる(仕様 §3.4)。
  ///
  /// `_grid` / `_score` は `this._grid` の initializing formal にしない
  /// — そのまま使うと名前付き引数がフィールド名の `_grid` / `_score` に
  /// なり、private な内部表現が公開 API に漏れる。
  BonusSession({
    required this.repository,
    required BonusGrid grid,
    required int score,
    int repairsUsed = 0,
    Random? random,
  })  : _grid = grid, // ignore: prefer_initializing_formals
        _score = score, // ignore: prefer_initializing_formals
        _repairsUsed = repairsUsed.clamp(0, kBonusRepairLimit),
        _random = random ?? Random();

  BonusGrid get grid => _grid;
  int get score => _score;

  /// 終わっていなければ null。
  BonusOutcome? get outcome => _outcome;

  bool get isOver => _outcome != null;
  bool get isCleared => _outcome == BonusOutcome.cleared;
  bool get isGameOver => _outcome == BonusOutcome.gameOver;

  /// このゲームで盤面を入れ替えた回数。
  int get repairsUsed => _repairsUsed;

  /// 残りの入れ替え回数。0 になると、次に詰んだ時点でゲームオーバー。
  int get repairsLeft => kBonusRepairLimit - _repairsUsed;

  /// 直前の手で詰みの修復が書き換えたマス数。0 なら修復していない。
  ///
  /// 詰みは 1 ゲームに 13 回、およそ 8 タップに 1 回起きる(仕様 §3.2)。
  /// 無言で盤面が書き換わると理不尽に見えるので、UI がこれを見て短い
  /// 通知を出す。
  int get lastRepairedCells => _lastRepairedCells;

  /// 直近に成立した手。まだ 1 手も打っていなければ null。
  ///
  /// 盤面のアニメーションが「何がどこへ動いたか」を必要とする。前後の
  /// 盤面を差分しても同値のマスの対応が復元できないので、盤面が返した
  /// ものをそのまま渡す(仕様 §4.3)。
  BonusMerge? get lastMerge => _lastMerge;

  /// 成立した手の数。[lastMerge] の中身が同じでも手が進んだことを
  /// 見分けるために使う(アニメーションの再生の引き金)。
  int get moveCount => _moveCount;

  /// 結果の書き込みが確定するまで true。
  ///
  /// [ResultScreen] と同じ理由で必要。時間切れ(ここではクリア)の瞬間は
  /// 書き込みが未完了で [bestUpdated] が false のままなので、そのまま
  /// 描くと古いベストが一瞬出てから「ベスト更新!」に切り替わる。
  bool get isSavingResult => _isSavingResult;

  bool get bestUpdated => _bestUpdated;
  int get bestScore => repository.bestScore;

  void tap(int index) {
    if (_disposed || isOver) return;
    // 残りが無いときだけ修復を断る。断った結果詰んでいたら、その手を
    // 最後にゲームオーバー(仕様 §3.1)。打った手そのものは合法なので
    // 得点は加算する。
    final merge = _grid.tap(index, _random, repairIfStuck: repairsLeft > 0);
    // 不正な手では盤面が変わらないので、再描画も促さない。
    if (merge == null) return;

    _lastMerge = merge;
    _moveCount++;

    _grid = merge.grid;
    _score += merge.gained;
    _lastRepairedCells = merge.repairedCells;
    if (merge.repairedCells > 0) _repairsUsed++;

    if (merge.cleared) {
      _outcome = BonusOutcome.cleared;
      _finish();
    } else if (merge.isStuck) {
      _outcome = BonusOutcome.gameOver;
      _finish();
    } else {
      // 1 手ごとに保存する。所要 5 分前後のゲームで、電話や
      // バックグラウンド化による中断は普通に起きる(仕様 §4.3)。
      repository.saveProgress(_grid, _score, _repairsUsed).ignore();
    }
    notifyListeners();
  }

  /// 途中でやめる。その時点のスコアを確定させる。
  void giveUp() {
    if (_disposed || isOver) return;
    _outcome = BonusOutcome.gaveUp;
    _finish();
    notifyListeners();
  }

  void _finish() {
    // isOver は tap()/giveUp() の呼び出し中に同期で確定させる。画面遷移や
    // 入力ロックがこれを await 抜きで即座に見られる必要があるため、
    // 下の非同期の保存処理を待ってはいけない(TimeAttackSession._finish と
    // 同じ理由)。
    _isSavingResult = true;
    repository.finish(_score).then(
      (improved) {
        _isSavingResult = false;
        _bestUpdated = improved;
        if (_disposed) return;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        // 書き込みが失敗しても isSavingResult を true に固定したままに
        // しない。結果画面がベスト行を永久に伏せてしまう。
        _isSavingResult = false;
        if (_disposed) return;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
