import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/bonus_repository.dart';
import '../domain/bonus/bonus_grid.dart';

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
  bool _cleared = false;
  bool _gaveUp = false;
  int _lastRepairedCells = 0;
  bool _isSavingResult = false;
  bool _bestUpdated = false;
  bool _disposed = false;

  /// [grid] と [score] は新規なら `BonusGrid.deal(...)` と 0、再開なら
  /// [BonusRepository] に保存されていた値を渡す。
  ///
  /// `_grid` / `_score` は `this._grid` の initializing formal にしない
  /// — そのまま使うと名前付き引数がフィールド名の `_grid` / `_score` に
  /// なり、private な内部表現が公開 API に漏れる。
  BonusSession({
    required this.repository,
    required BonusGrid grid,
    required int score,
    Random? random,
  })  : _grid = grid, // ignore: prefer_initializing_formals
        _score = score, // ignore: prefer_initializing_formals
        _random = random ?? Random();

  BonusGrid get grid => _grid;
  int get score => _score;
  bool get isCleared => _cleared;
  bool get isOver => _cleared || _gaveUp;

  /// 直前の手で詰みの修復が書き換えたマス数。0 なら修復していない。
  ///
  /// 詰みは 1 ゲームに 13 回、およそ 8 タップに 1 回起きる(仕様 §3.2)。
  /// 無言で盤面が書き換わると理不尽に見えるので、UI がこれを見て短い
  /// 通知を出す。
  int get lastRepairedCells => _lastRepairedCells;

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
    final merge = _grid.tap(index, _random);
    // 不正な手では盤面が変わらないので、再描画も促さない。
    if (merge == null) return;

    _grid = merge.grid;
    _score += merge.gained;
    _lastRepairedCells = merge.repairedCells;

    if (merge.cleared) {
      _cleared = true;
      _finish();
    } else {
      // 1 手ごとに保存する。所要 5 分前後のゲームで、電話や
      // バックグラウンド化による中断は普通に起きる(仕様 §4.3)。
      repository.saveProgress(_grid, _score).ignore();
    }
    notifyListeners();
  }

  /// 途中でやめる。その時点のスコアを確定させる。
  void giveUp() {
    if (_disposed || isOver) return;
    _gaveUp = true;
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
