# ボーナスゲーム 1 日 5 回まで 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ボーナスゲームを 1 日 1 回から 1 日 5 回までにし、タイムアタックで 5 問クリアするたびに 1 回分たまるようにする。

**Architecture:** `BonusTicket` を「日付 2 つ」から「日付 1 つ + 獲得数 + 消費数」に作り直す。日付では数が数えられないので表現ごと変える。既に公開済みの web 版で古い形式の保存データが存在するため、読み込み時に移行する。ボーナスゲーム本体のルールは一切変えない。

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2。**新しい依存パッケージは追加しない。**

**仕様書:** [docs/superpowers/specs/2026-09-06-bonus-plays-per-day-design.md](../specs/2026-09-06-bonus-plays-per-day-design.md)

## Global Constraints

- **Flutter は PATH に無い。** `C:/flutter/bin/flutter.bat` と `C:/flutter/bin/dart.bat` をフルパスで呼ぶ。シェルの状態はツール呼び出し間で保持されない。
- **このリポジトリのパスからは `flutter analyze` を実行できない**（非 ASCII パスで Dart 解析サーバがクラッシュする）。`flutter build apk` / `appbundle` も AGP が拒否する。`flutter test` と `flutter build web` は動く。アナライザは ASCII のパスへコピーして走らせる。
- 作業ブランチは `feat/bonus-plays-per-day`。`main` に直接コミットしない。
- **既存の 516 テストのうち、`BonusTicket` の日付 API に依存するものは意図的に置き換える**（Task 1 参照）。それ以外は 1 つも壊さない。
- `lib/domain/` 配下では `package:flutter/` を import しない（`test/domain/domain_purity_test.dart` が検査する）。
- `analysis_options.yaml` は `flutter_lints` + `prefer_final_locals` + `avoid_print`。
- 既存の日本語 doc コメントの流儀に合わせる。**「何を」ではなく「なぜ」を書く。**
- Flutter コマンドが `Upgrading analysis_options.yaml to exclude build and platform directories.` を出して同ファイルが変更扱いになったら SDK の正常な挙動。**コミットに含めない。**

## 既存コードの読みどころ

着手前に必ず読むこと。

- `lib/domain/bonus_ticket.dart` — 作り直す本体
- `lib/data/bonus_repository.dart` — `load` / `_writeNow` / `_writeQueue`
- `lib/ui/home_screen.dart` — `_BonusEntryState._entry` と `_BonusUnlockNotice`、`_startTimeAttack` の `onFinished`
- `test/domain/bonus_ticket_test.dart` — **このファイルは書き換わる**
- `test/ui/bonus_home_entry_test.dart` / `test/ui/bonus_unlock_test.dart` — 旧 API を使っている

---

### Task 1: `BonusTicket` を回数制に作り直す

**Files:**
- Modify: `lib/domain/bonus_ticket.dart`（全面書き換え）
- Modify: `test/domain/bonus_ticket_test.dart`（**全面書き換え**）

**Interfaces:**
- Consumes: なし
- Produces:
  - `const int kBonusPlaysPerDay = 5;`
  - `class BonusTicket` — `BonusTicket({String? day, int earned = 0, int played = 0})`、`String? get day`、`int get earned`、`int get played`、`bool earn(String today)`、`bool isAvailable(String today)`、`void consume(String today)`、`int playsLeft(String today)`
  - `kBonusUnlockClears` と `bonusDateKey` はそのまま残す

**このタスクは既存テストを壊す。それが正しい。** 旧 API の `unlockedOn` / `playedOn` は無くなり、`test/domain/bonus_ticket_test.dart` の 13 テストは書き換えになる。**特に「遊んだ後に 5 問クリアしても権利は復活しない」というテストは、仕様上まさに逆になった** — 回数制では復活する。このテストは**削除して置き換える**こと。残そうとしてはいけない。

- [ ] **Step 1: テストを全面的に書き換える**

`test/domain/bonus_ticket_test.dart` を次で置き換える。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus_ticket.dart';

const String d1 = '2026-09-06';
const String d2 = '2026-09-07';

void main() {
  group('bonusDateKey', () {
    test('yyyy-MM-dd に整形する', () {
      expect(bonusDateKey(DateTime(2026, 9, 6)), '2026-09-06');
      expect(bonusDateKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(bonusDateKey(DateTime(2026, 1, 1, 23, 59, 59)), '2026-01-01');
    });

    test('日付が変わる瞬間で切り替わる', () {
      expect(bonusDateKey(DateTime(2026, 9, 6, 23, 59, 59)), '2026-09-06');
      expect(bonusDateKey(DateTime(2026, 9, 7, 0, 0, 0)), '2026-09-07');
    });
  });

  group('定数', () {
    test('解禁に必要なクリア数は 5', () => expect(kBonusUnlockClears, 5));
    test('1 日に遊べる回数は 5', () => expect(kBonusPlaysPerDay, 5));
  });

  group('獲得と消費', () {
    test('初期状態では遊べない', () {
      final t = BonusTicket();
      expect(t.isAvailable(d1), isFalse);
      expect(t.playsLeft(d1), 0);
    });

    test('1 回獲得すると 1 回遊べる', () {
      final t = BonusTicket();
      expect(t.earn(d1), isTrue);
      expect(t.isAvailable(d1), isTrue);
      expect(t.playsLeft(d1), 1);
    });

    test('消費すると残りが減る', () {
      final t = BonusTicket();
      t.earn(d1);
      t.consume(d1);
      expect(t.playsLeft(d1), 0);
      expect(t.isAvailable(d1), isFalse);
    });

    test('獲得した数より多く遊べない', () {
      final t = BonusTicket();
      t.earn(d1);
      t.consume(d1);
      t.consume(d1); // 余分な消費
      expect(t.playsLeft(d1), 0);
      expect(t.played, lessThanOrEqualTo(t.earned),
          reason: '獲得していない分まで消費されている');
    });

    test('獲得 → 消費 → 獲得で、また遊べるようになる', () {
      // **回数制で最も変わる点。** 1 日 1 回だった頃は、一度遊んだあとに
      // もう一度 5 問クリアしても権利は復活しなかった。
      final t = BonusTicket();
      t.earn(d1);
      t.consume(d1);
      expect(t.isAvailable(d1), isFalse);

      expect(t.earn(d1), isTrue);
      expect(t.isAvailable(d1), isTrue);
      expect(t.playsLeft(d1), 1);
    });

    test('獲得を貯められる', () {
      final t = BonusTicket();
      t.earn(d1);
      t.earn(d1);
      t.earn(d1);
      expect(t.playsLeft(d1), 3);
      t.consume(d1);
      expect(t.playsLeft(d1), 2);
    });
  });

  group('1 日の上限', () {
    test('5 回まで貯まる', () {
      final t = BonusTicket();
      for (var i = 0; i < kBonusPlaysPerDay; i++) {
        expect(t.earn(d1), isTrue, reason: '${i + 1} 回目の獲得が失敗した');
      }
      expect(t.playsLeft(d1), kBonusPlaysPerDay);
    });

    test('6 回目は増えず false を返す', () {
      final t = BonusTicket();
      for (var i = 0; i < kBonusPlaysPerDay; i++) {
        t.earn(d1);
      }
      expect(t.earn(d1), isFalse);
      expect(t.playsLeft(d1), kBonusPlaysPerDay);
      expect(t.earned, kBonusPlaysPerDay);
    });

    test('使い切ったあとに勝っても増えない', () {
      final t = BonusTicket();
      for (var i = 0; i < kBonusPlaysPerDay; i++) {
        t.earn(d1);
        t.consume(d1);
      }
      expect(t.earn(d1), isFalse);
      expect(t.isAvailable(d1), isFalse);
    });

    test('earn の返り値は「増えたか」であって「遊べるようになったか」ではない', () {
      // 既に遊べる状態で 2 個目を獲得しても true。リザルトの告知は
      // これで出すので、獲得のたびに true になる必要がある（仕様 §2.2）。
      final t = BonusTicket();
      t.earn(d1);
      expect(t.isAvailable(d1), isTrue);
      expect(t.earn(d1), isTrue, reason: '2 個目の獲得が false になっている');
    });
  });

  group('日付をまたぐ', () {
    test('翌日にはカウンタがリセットされる', () {
      final t = BonusTicket();
      t.earn(d1);
      t.earn(d1);
      expect(t.playsLeft(d2), 0, reason: '前日の分が翌日に残っている');
    });

    test('翌日に獲得するとその日の 1 回目になる', () {
      final t = BonusTicket();
      for (var i = 0; i < kBonusPlaysPerDay; i++) {
        t.earn(d1);
        t.consume(d1);
      }
      expect(t.earn(d2), isTrue);
      expect(t.playsLeft(d2), 1);
      expect(t.earned, 1, reason: '前日のカウンタが引き継がれている');
      expect(t.played, 0);
    });

    test('前日に獲得して遊ばなかった分は消える', () {
      final t = BonusTicket(day: d1, earned: 3, played: 0);
      expect(t.playsLeft(d2), 0);
      expect(t.isAvailable(d2), isFalse);
    });

    test('別の日の consume はカウンタを壊さない', () {
      final t = BonusTicket(day: d1, earned: 2, played: 0);
      t.consume(d2);
      expect(t.played, 0, reason: '別の日の消費がカウンタに入った');
      expect(t.playsLeft(d1), 2);
    });
  });

  group('復元', () {
    test('保存した値から状態を復元できる', () {
      final t = BonusTicket(day: d1, earned: 3, played: 2);
      expect(t.day, d1);
      expect(t.earned, 3);
      expect(t.played, 2);
      expect(t.playsLeft(d1), 1);
      expect(t.isAvailable(d1), isTrue);
    });

    test('上限を超える earned は丸める', () {
      final t = BonusTicket(day: d1, earned: 99, played: 0);
      expect(t.earned, kBonusPlaysPerDay);
    });

    test('負の値は 0 に丸める', () {
      final t = BonusTicket(day: d1, earned: -3, played: -1);
      expect(t.earned, 0);
      expect(t.played, 0);
    });

    test('played が earned を超えていたら earned に丸める', () {
      // 回数が増える側ではなく減る側に倒す（仕様 §6）。
      final t = BonusTicket(day: d1, earned: 2, played: 5);
      expect(t.played, 2);
      expect(t.playsLeft(d1), 0);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus_ticket_test.dart`
Expected: FAIL — `kBonusPlaysPerDay` が未定義、`playsLeft` が未定義

- [ ] **Step 3: 実装を書き換える**

`lib/domain/bonus_ticket.dart` の `BonusTicket` クラスを置き換える。
`kBonusUnlockClears` と `bonusDateKey` は**そのまま残す**（doc コメントの
「1 日 1 回の報酬」という表現だけ「1 日 5 回まで」に直す）。

```dart
/// 1 日に遊べるボーナスゲームの最大回数。
///
/// 回数は自動で配られない。タイムアタックで [kBonusUnlockClears] 問
/// クリアするたびに 1 回分たまり、ここで頭打ちになる。5 回遊ぶには
/// タイムアタックを 5 回勝つ必要がある（仕様 §1）。
const int kBonusPlaysPerDay = 5;

/// ボーナスゲームを今日あと何回遊べるかを数える、プラットフォーム非依存の
/// 純粋なロジック。盤面のルールを一切知らない。
///
/// 保存はしない（既存 `AdPolicy` と同じ考え方）。呼び出し側が [day] /
/// [earned] / [played] を読み出して永続化し、次回起動時にコンストラクタへ
/// 渡し直す。
///
/// **日付 2 つ（解禁した日・遊んだ日）ではなく、日付 1 つとカウンタ 2 つで
/// 持つ。** 日付では数が数えられないため、1 日 5 回にするには表現ごと
/// 変える必要があった（仕様 §2.1）。
class BonusTicket {
  String? _day;
  int _earned;
  int _played;

  /// [earned] は 0 以上 [kBonusPlaysPerDay] 以下、[played] は 0 以上
  /// [earned] 以下に丸める。壊れた保存データを読んでも、遊べる回数が
  /// **増える側ではなく減る側**に倒す（仕様 §6）。
  BonusTicket({String? day, int earned = 0, int played = 0})
      : _day = day, // ignore: prefer_initializing_formals
        _earned = earned.clamp(0, kBonusPlaysPerDay),
        _played = played.clamp(0, earned.clamp(0, kBonusPlaysPerDay));

  /// このカウンタが属するローカル日付。未設定なら null。
  String? get day => _day;

  /// [day] に獲得した回数。
  int get earned => _earned;

  /// [day] に開始した回数。
  int get played => _played;

  /// 今日あと何回遊べるか。日付が違えば 0。
  int playsLeft(String today) => _day == today ? _earned - _played : 0;

  /// 今日ボーナスゲームを遊べるか。
  bool isAvailable(String today) => playsLeft(today) > 0;

  /// タイムアタックで [kBonusUnlockClears] 問以上クリアしたときに呼ぶ。
  ///
  /// **返り値は「[earned] が増えたか」であって「遊べるようになったか」では
  /// ない。** 既に遊べる状態で 2 個目を獲得した場合も true になる。
  /// リザルトの告知はこの返り値で出すので、獲得のたびに true である
  /// 必要がある（仕様 §2.2）。
  bool earn(String today) {
    if (_day != today) {
      // 日付が変わったらカウンタごとリセットする。繰り越しはない。
      _day = today;
      _earned = 0;
      _played = 0;
    }
    if (_earned >= kBonusPlaysPerDay) return false;
    _earned++;
    return true;
  }

  /// ボーナスゲームを**開始した**ときに呼ぶ。
  ///
  /// 完了時ではなく開始時に消費する。完了時にすると、強制終了することで
  /// 無限にリトライできてしまう。中断で回数を失う実害は、途中の盤面を
  /// 永続化して再開できるようにすることで消している（仕様 §2.3）。
  ///
  /// 日付が違う場合と、獲得した分をすでに使い切っている場合は何もしない。
  /// [isAvailable] を通らずに呼ばれてもカウンタが壊れないようにするため。
  void consume(String today) {
    if (_day != today) return;
    if (_played >= _earned) return;
    _played++;
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus_ticket_test.dart`
Expected: PASS

- [ ] **Step 5: 丸めが効いていることを確認する**

コンストラクタの `_played = played.clamp(0, earned.clamp(0, kBonusPlaysPerDay))`
を一時的に `_played = played` に変える。

Run: `C:/flutter/bin/flutter.bat test test/domain/bonus_ticket_test.dart`
Expected: **FAIL** — 「played が earned を超えていたら earned に丸める」と
「負の値は 0 に丸める」が落ちる

確認したら元に戻し、再実行して PASS を確認する。

- [ ] **Step 6: 呼び出し側がコンパイルできないことを確認する**

Run: `C:/flutter/bin/flutter.bat test`
Expected: **FAIL（コンパイルエラー）** — `lib/data/bonus_repository.dart` と
`lib/ui/home_screen.dart` が `unlockedOn` / `playedOn` を参照している。

**このタスクはここで止めず、Task 2 と Task 3 を終えるまでコミットしない。**
`BonusTicket` の書き換えだけでは `flutter test` が通らないため、
Task 1〜3 は 1 つのコミットにまとめる。Task 4 は独立してコミットできる。

---

### Task 2: 移行と永続化

**Files:**
- Modify: `lib/data/bonus_repository.dart`
- Test: `test/data/bonus_migration_test.dart`

**Interfaces:**
- Consumes: Task 1 の `BonusTicket({day, earned, played})` / `kBonusPlaysPerDay`
- Produces: `BonusRepository` の `ticket` が新しい `BonusTicket` を返す。保存形式は `version: 2`

**`consume` の穴に注意:** `BonusTicket.consume` は残りが無ければ何もしない（カウンタを壊さないための設計）。その結果 `BonusRepository.startGame` は**回数が無くても盤面を書いてゲームを始められる**。今それを止めているのはホーム画面がボタンを無効にしていることだけで、ドメイン側の防御ではない。この計画では構造を変えないが、カウンタが壊れないことはテストで押さえる。

- [ ] **Step 1: 失敗するテストを書く**

`test/data/bonus_migration_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/data/bonus_repository.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String today = '2026-09-06';
const String yesterday = '2026-09-05';

BonusGrid playableGrid() => BonusGrid.of(const [
      1, 1, 3, 1, 2, //
      3, 1, 2, 3, 1, //
      2, 3, 1, 2, 3, //
      1, 2, 3, 1, 2, //
      3, 1, 2, 3, 1, //
    ]);

Future<BonusRepository> loaded() async {
  final repo = BonusRepository();
  await repo.load();
  return repo;
}

void setPrefs(Map<String, dynamic> json) {
  SharedPreferences.setMockInitialValues({'make10.bonus': jsonEncode(json)});
}

void main() {
  group('旧形式(version 1)からの移行', () {
    test('どちらの日付も無ければ 0 回', () async {
      setPrefs({'version': 1, 'bestScore': 100});
      final repo = await loaded();
      expect(repo.ticket.playsLeft(today), 0);
      expect(repo.bestScore, 100, reason: 'ベストスコアまで失われている');
    });

    test('unlockedOn だけなら 1 回遊べる', () async {
      // 今日 5 問クリアして、まだ遊んでいない人。**移行で消してはいけない。**
      setPrefs({'version': 1, 'unlockedOn': today});
      final repo = await loaded();
      expect(repo.ticket.playsLeft(today), 1);
      expect(repo.ticket.isAvailable(today), isTrue);
    });

    test('playedOn だけなら獲得も消費も 1', () async {
      setPrefs({'version': 1, 'playedOn': today});
      final repo = await loaded();
      expect(repo.ticket.earned, 1);
      expect(repo.ticket.played, 1);
      expect(repo.ticket.playsLeft(today), 0);
    });

    test('両方が同じ日なら獲得も消費も 1', () async {
      setPrefs({'version': 1, 'unlockedOn': today, 'playedOn': today});
      final repo = await loaded();
      expect(repo.ticket.day, today);
      expect(repo.ticket.earned, 1);
      expect(repo.ticket.played, 1);
    });

    test('unlockedOn の方が新しければ今日 1 回遊べる', () async {
      setPrefs({'version': 1, 'unlockedOn': today, 'playedOn': yesterday});
      final repo = await loaded();
      expect(repo.ticket.day, today);
      expect(repo.ticket.playsLeft(today), 1);
    });

    test('playedOn の方が新しければ今日は遊べない', () async {
      setPrefs({'version': 1, 'unlockedOn': yesterday, 'playedOn': today});
      final repo = await loaded();
      expect(repo.ticket.day, today);
      expect(repo.ticket.playsLeft(today), 0);
    });

    test('移行後に保存すると新形式になる', () async {
      setPrefs({'version': 1, 'unlockedOn': today});
      final repo = await loaded();
      await repo.earn(today); // 保存が走る

      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString('make10.bonus')!)
          as Map<String, dynamic>;
      expect(raw['version'], 2);
      expect(raw['day'], today);
      expect(raw['earned'], 2);
      expect(raw.containsKey('unlockedOn'), isFalse,
          reason: '古いキーを書き続けている');
      expect(raw.containsKey('playedOn'), isFalse);
    });
  });

  group('新形式(version 2)', () {
    test('往復できる', () async {
      setPrefs({
        'version': 2,
        'bestScore': 859,
        'day': today,
        'earned': 3,
        'played': 2,
      });
      final repo = await loaded();
      expect(repo.bestScore, 859);
      expect(repo.ticket.earned, 3);
      expect(repo.ticket.played, 2);
      expect(repo.ticket.playsLeft(today), 1);
    });

    test('day があれば旧キーは無視する', () async {
      // 新旧のビルドを行き来した端末で、古い値に引きずられないこと。
      setPrefs({
        'version': 2,
        'day': today,
        'earned': 4,
        'played': 1,
        'unlockedOn': yesterday,
        'playedOn': yesterday,
      });
      final repo = await loaded();
      expect(repo.ticket.day, today);
      expect(repo.ticket.earned, 4);
      expect(repo.ticket.played, 1);
    });

    test('earned が上限を超えていたら丸める', () async {
      setPrefs({'version': 2, 'day': today, 'earned': 99, 'played': 0});
      final repo = await loaded();
      expect(repo.ticket.earned, kBonusPlaysPerDay);
    });

    test('played が earned を超えていたら丸める', () async {
      setPrefs({'version': 2, 'day': today, 'earned': 2, 'played': 9});
      final repo = await loaded();
      expect(repo.ticket.played, 2);
    });

    test('型が違えば 0 として読む', () async {
      setPrefs({
        'version': 2,
        'day': today,
        'earned': 'たくさん',
        'played': null,
      });
      final repo = await loaded();
      expect(repo.ticket.earned, 0);
      expect(repo.ticket.played, 0);
    });
  });

  group('ゲームの開始と終了', () {
    test('開始で 1 回消費し、途中状態を書く', () async {
      setPrefs({'version': 2, 'day': today, 'earned': 3, 'played': 0});
      final repo = await loaded();
      await repo.startGame(today, playableGrid());
      expect(repo.ticket.played, 1);
      expect(repo.ticket.playsLeft(today), 2);
      expect(repo.hasInProgress, isTrue);

      final reloaded = await loaded();
      expect(reloaded.ticket.played, 1);
      expect(reloaded.ticket.playsLeft(today), 2);
    });

    test('終了しても残り回数は戻らない', () async {
      setPrefs({'version': 2, 'day': today, 'earned': 3, 'played': 0});
      final repo = await loaded();
      await repo.startGame(today, playableGrid());
      await repo.finish(500);
      expect(repo.ticket.playsLeft(today), 2,
          reason: '終了で消費が取り消されている');
      expect(repo.hasInProgress, isFalse);
    });

    test('回数が無いのに開始しても消費が負にならない', () async {
      // `consume` は残りが無ければ黙って何もしない。つまり `startGame` は
      // 回数が無くてもゲームを始められてしまい、今それを止めているのは
      // ホーム画面がボタンを無効にしていることだけである。カウンタが
      // 壊れないことだけはここで担保しておく。
      setPrefs({'version': 2, 'day': today, 'earned': 1, 'played': 1});
      final repo = await loaded();
      await repo.startGame(today, playableGrid());
      expect(repo.ticket.played, 1, reason: '獲得していない分まで消費された');
      expect(repo.ticket.earned, 1);
    });

    test('earn は増えたときだけ true', () async {
      setPrefs({
        'version': 2,
        'day': today,
        'earned': kBonusPlaysPerDay,
        'played': 0,
      });
      final repo = await loaded();
      expect(await repo.earn(today), isFalse);
    });
  });

  group('壊れたデータ', () {
    test('JSON として読めなければ既定値で続行する', () async {
      SharedPreferences.setMockInitialValues({'make10.bonus': 'not json'});
      final repo = await loaded();
      expect(repo.bestScore, 0);
      expect(repo.ticket.playsLeft(today), 0);
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_migration_test.dart`
Expected: FAIL（コンパイルエラー — Task 1 で旧 API が消えているため
`bonus_repository.dart` が通らない）

- [ ] **Step 3: `load()` を書き換える**

`lib/data/bonus_repository.dart` の `load()` の中、`ticket` を作る部分を
次に置き換える。

```dart
        ticket = _decodeTicket(data);
```

ファイル末尾（`_decodeGrid` の隣）に追加する。

```dart
/// 保存された JSON から権利を復元する。
///
/// **version 1（日付 2 つ）の保存データが実際に端末に存在する。** web 版は
/// 公開済みで、遊んだ人のデータがある。捨てるとその日の権利が消えるので、
/// 読み込み時に新しい形へ移す（仕様 §3）。
///
/// `day` があれば新形式として読み、旧キーは見ない。新旧のビルドを行き来
/// した端末で、古い値に引きずられないようにするため。
BonusTicket _decodeTicket(Map<String, dynamic> data) {
  final day = data['day'];
  if (day is String) {
    final earned = data['earned'];
    final played = data['played'];
    return BonusTicket(
      day: day,
      earned: earned is int ? earned : 0,
      played: played is int ? played : 0,
    );
  }

  // ここから下は version 1 からの移行。
  final unlockedOn = data['unlockedOn'];
  final playedOn = data['playedOn'];
  final unlocked = unlockedOn is String ? unlockedOn : null;
  final played = playedOn is String ? playedOn : null;

  if (unlocked == null && played == null) return BonusTicket();
  if (played == null) {
    // 今日獲得してまだ遊んでいない人。1 回分を残す。
    return BonusTicket(day: unlocked, earned: 1, played: 0);
  }
  if (unlocked == null || played.compareTo(unlocked) >= 0) {
    // 遊んだ日が同じか新しい。遊んだのなら獲得もしていたはず。
    return BonusTicket(day: played, earned: 1, played: 1);
  }
  return BonusTicket(day: unlocked, earned: 1, played: 0);
}
```

`bonus_ticket.dart` の import は既にある。

- [ ] **Step 4: `_writeNow()` を書き換える**

```dart
      jsonEncode({
        'version': 2,
        'bestScore': _bestScore,
        'day': _ticket.day,
        'earned': _ticket.earned,
        'played': _ticket.played,
        if (grid != null)
          'inProgress': {
            'grid': grid.cells,
            'score': _inProgressScore,
            'repairsUsed': _inProgressRepairsUsed,
          },
      }),
```

- [ ] **Step 5: 日付の比較が文字列で正しいことを確認する**

`_decodeTicket` は `played.compareTo(unlocked) >= 0` で日付の新旧を比べる。
`yyyy-MM-dd` は**ゼロ埋めされた固定長**なので、辞書順の比較が日付の
前後と一致する。`bonusDateKey` が `padLeft` しているのはこのため。
形式を変えるとここが静かに壊れる。

Run: `C:/flutter/bin/flutter.bat test test/data/bonus_migration_test.dart`
Expected: この時点ではまだ `home_screen.dart` がコンパイルできず FAIL。
Task 3 まで進めてから確認する。

---

### Task 3: ホーム画面の 4 状態と回数表示

**Files:**
- Modify: `lib/ui/home_screen.dart`（`_BonusEntryState._entry` と `_startTimeAttack`）
- Modify: `test/ui/bonus_home_entry_test.dart`（旧形式の JSON を新形式に）
- Test: `test/ui/bonus_plays_left_test.dart`

**Interfaces:**
- Consumes: `BonusTicket.playsLeft` / `earned` / `day`、`kBonusPlaysPerDay`
- Produces: なし（画面の中だけ）

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_plays_left_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus_ticket.dart';
import 'package:make10/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

String today() => bonusDateKey(DateTime.now());

List<int> playableCells() => const [
      1, 1, 3, 1, 2, //
      3, 1, 2, 3, 1, //
      2, 3, 1, 2, 3, //
      1, 2, 3, 1, 2, //
      3, 1, 2, 3, 1, //
    ];

void setBonus({
  int bestScore = 0,
  String? day,
  int earned = 0,
  int played = 0,
  bool inProgress = false,
}) {
  SharedPreferences.setMockInitialValues({
    'make10.bonus': jsonEncode({
      'version': 2,
      'bestScore': bestScore,
      'day': day,
      'earned': earned,
      'played': played,
      if (inProgress)
        'inProgress': {'grid': playableCells(), 'score': 0, 'repairsUsed': 0},
    }),
  });
}

Future<void> pumpHome(WidgetTester tester) async {
  // 問題データを読み直させる。これを忘れると 2 つ目以降のテストで
  // pumpAndSettle が返らない（app_boot_test.dart に同じ注記がある）。
  await rootBundle.evict('assets/puzzles.json');
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: HomeScreen())),
  );
  await tester.pumpAndSettle();
}

TextButton bonusButton(WidgetTester tester) => tester.widget<TextButton>(
      find.ancestor(
        of: find.textContaining('ボーナスゲーム'),
        matching: find.byType(TextButton),
      ),
    );

void main() {
  testWidgets('残り 3 回なら「あと 3 回」と出て押せる', (tester) async {
    setBonus(day: today(), earned: 3, played: 0);
    await pumpHome(tester);
    expect(find.text('★ ボーナスゲーム（あと 3 回）'), findsOneWidget);
    expect(bonusButton(tester).onPressed, isNotNull);
  });

  testWidgets('残り 1 回なら「あと 1 回」', (tester) async {
    setBonus(day: today(), earned: 3, played: 2);
    await pumpHome(tester);
    expect(find.text('★ ボーナスゲーム（あと 1 回）'), findsOneWidget);
  });

  testWidgets('残り 0・上限未満なら条件を出して押せない', (tester) async {
    setBonus(day: today(), earned: 2, played: 2);
    await pumpHome(tester);
    expect(
      find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
      findsOneWidget,
    );
    expect(bonusButton(tester).onPressed, isNull);
  });

  testWidgets('未獲得も同じ文言', (tester) async {
    // やるべきことが同じなので区別しない（仕様 §4）。
    setBonus();
    await pumpHome(tester);
    expect(
      find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
      findsOneWidget,
    );
    expect(bonusButton(tester).onPressed, isNull);
  });

  testWidgets('5 回使い切ったら「また明日」とベスト', (tester) async {
    setBonus(
      bestScore: 859,
      day: today(),
      earned: kBonusPlaysPerDay,
      played: kBonusPlaysPerDay,
    );
    await pumpHome(tester);
    expect(find.text('ボーナスゲーム（また明日） ベスト 859'), findsOneWidget);
    expect(bonusButton(tester).onPressed, isNull);
  });

  testWidgets('中断があれば残り回数より優先される', (tester) async {
    setBonus(day: today(), earned: 4, played: 1, inProgress: true);
    await pumpHome(tester);
    expect(find.text('ボーナスゲーム（続きから）'), findsOneWidget);
    expect(bonusButton(tester).onPressed, isNotNull);
  });

  testWidgets('前日の残りは翌日に持ち越されない', (tester) async {
    final y = bonusDateKey(DateTime.now().subtract(const Duration(days: 1)));
    setBonus(day: y, earned: 5, played: 0);
    await pumpHome(tester);
    expect(
      find.text('ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）'),
      findsOneWidget,
    );
  });

  testWidgets('既存の 3 つの入口は残っている', (tester) async {
    setBonus();
    await pumpHome(tester);
    expect(find.text('プラクティス'), findsOneWidget);
    expect(find.text('タイムアタック'), findsOneWidget);
    expect(find.text('統計'), findsOneWidget);
  });
}
```

- [ ] **Step 2: `_entry` を書き換える**

`lib/ui/home_screen.dart` の `_BonusEntryState._entry` を置き換える。

```dart
  Widget _entry(BuildContext context, BonusRepository bonus) {
    final today = bonusDateKey(DateTime.now());
    final ticket = bonus.ticket;
    final left = ticket.playsLeft(today);
    final String label;
    final bool enabled;
    if (bonus.hasInProgress) {
      // 中断が最優先。その 1 回は消費済みなので、再開せずに別の回を
      // 始められると回数が合わなくなる（仕様 §4）。
      label = 'ボーナスゲーム（続きから）';
      enabled = true;
    } else if (left > 0) {
      label = '★ ボーナスゲーム（あと $left 回）';
      enabled = true;
    } else if (ticket.day == today && ticket.earned >= kBonusPlaysPerDay) {
      label = 'ボーナスゲーム（また明日） ベスト ${bonus.bestScore}';
      enabled = false;
    } else {
      // 「まだ 1 回も獲得していない」と「獲得した分を使い切ったが今日の
      // 上限には届いていない」は、どちらも次にやることが「タイムアタックを
      // 勝つ」で同じ。区別しても情報が増えないので同じ文言にする（仕様 §4）。
      label = 'ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）';
      enabled = false;
    }

    return TextButton(
      style: widget.scale > 1.0
          ? TextButton.styleFrom(
              textStyle: TextStyle(fontSize: 14 * widget.scale))
          : null,
      onPressed: enabled && !_starting ? () => _start(context, bonus) : null,
      child: Text(label),
    );
  }
```

- [ ] **Step 3: 既存のホームのテストを新形式に直す**

`test/ui/bonus_home_entry_test.dart` の `setBonusPrefs` は
`unlockedOn` / `playedOn` を書いている。**移行の経路は Task 2 のテストが
見ているので、こちらは新形式に書き換える**（移行のテストとホーム画面の
テストを兼ねさせると、どちらが壊れたのか分からなくなる）。

`setBonusPrefs` を次に置き換え、呼び出し側の引数も合わせる。

```dart
void setBonusPrefs({
  int bestScore = 0,
  String? day,
  int earned = 0,
  int played = 0,
  bool inProgress = false,
  int inProgressScore = 0,
}) {
  SharedPreferences.setMockInitialValues({
    'make10.bonus': jsonEncode({
      'version': 2,
      'bestScore': bestScore,
      'day': day,
      'earned': earned,
      'played': played,
      if (inProgress)
        'inProgress': {
          'grid': playableCells(),
          'score': inProgressScore,
          'repairsUsed': 0,
        },
    }),
  });
}
```

呼び出しの対応は次のとおり。**アサーションの意図は変えないこと。**

| 元の呼び出し | 新しい呼び出し |
|---|---|
| `setBonusPrefs()` | `setBonusPrefs()` |
| `setBonusPrefs(unlockedOn: today())` | `setBonusPrefs(day: today(), earned: 1)` |
| `setBonusPrefs(bestScore: 994, unlockedOn: today(), playedOn: today())` | `setBonusPrefs(bestScore: 994, day: today(), earned: kBonusPlaysPerDay, played: kBonusPlaysPerDay)` |
| `setBonusPrefs(unlockedOn: today(), playedOn: today(), inProgress: true, ...)` | `setBonusPrefs(day: today(), earned: 1, played: 1, inProgress: true, ...)` |
| `setBonusPrefs(unlockedOn: yesterday())` | `setBonusPrefs(day: yesterday(), earned: 1)` |
| `setBonusPrefs(bestScore: 500, unlockedOn: yesterday(), playedOn: yesterday())` | `setBonusPrefs(bestScore: 500, day: yesterday(), earned: 1, played: 1)` |

「本日終了」を検査するテストは、**`earned` を上限まで埋める**必要がある
（そうしないと「タイムアタックで5問クリア」の方に落ちる）。「★ ボーナス
ゲーム」を期待していたテストは「★ ボーナスゲーム（あと 1 回）」になる。

- [ ] **Step 4: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: `test/ui/bonus_unlock_test.dart` が残っていれば失敗する
（Task 4 で直す）。それ以外は通ること。

- [ ] **Step 5: Task 1〜3 をまとめてコミット**

`BonusTicket` の書き換えは単独ではコンパイルが通らないので、ここまでを
1 つのコミットにする。

```bash
git add lib/domain/bonus_ticket.dart lib/data/bonus_repository.dart lib/ui/home_screen.dart test/domain/bonus_ticket_test.dart test/data/bonus_migration_test.dart test/ui/bonus_plays_left_test.dart test/ui/bonus_home_entry_test.dart
git commit -m "feat(bonus): count plays per day instead of allowing one"
```

---

### Task 4: タイムアタックのリザルトの告知

**Files:**
- Modify: `lib/ui/home_screen.dart`（`_startTimeAttack` と `_BonusUnlockNotice`）
- Modify: `test/ui/bonus_unlock_test.dart`
- Test: `test/ui/bonus_earn_notice_test.dart`

**Interfaces:**
- Consumes: `BonusRepository.earn` の返り値、`BonusTicket.playsLeft`
- Produces: なし

**告知はチケットの状態ではなく `earn` の結果で出す。** 今の
`_BonusUnlockNotice` は `ticket.isAvailable(today)` を見ているが、回数制では
**この勝負の前から回数が残っていた場合にも出てしまう** — 4 問しか
クリアしていない勝負でも「解禁!」と出る。この勝負で実際に増えたかどうかを
渡す必要がある。

- [ ] **Step 1: 失敗するテストを書く**

`test/ui/bonus_earn_notice_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/ui/home_screen.dart';

void main() {
  Future<void> pumpNotice(WidgetTester tester, int? playsLeft) async {
    final notifier = ValueNotifier<int?>(playsLeft);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BonusEarnNotice(earnedPlaysLeft: notifier)),
      ),
    );
  }

  testWidgets('獲得していなければ何も出さない', (tester) async {
    await pumpNotice(tester, null);
    expect(find.textContaining('ボーナスゲーム'), findsNothing);
  });

  testWidgets('獲得したら残り回数つきで出す', (tester) async {
    await pumpNotice(tester, 3);
    expect(find.text('ボーナスゲーム +1回'), findsOneWidget);
    expect(find.text('あと 3 回遊べます'), findsOneWidget);
  });

  testWidgets('残り 1 回でも出す', (tester) async {
    await pumpNotice(tester, 1);
    expect(find.text('あと 1 回遊べます'), findsOneWidget);
  });

  testWidgets('値が後から入ったら現れる', (tester) async {
    // onFinished は非同期に earn を終えるので、告知は後から出る。
    final notifier = ValueNotifier<int?>(null);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BonusEarnNotice(earnedPlaysLeft: notifier)),
      ),
    );
    expect(find.textContaining('ボーナスゲーム'), findsNothing);

    notifier.value = 2;
    await tester.pump();
    expect(find.text('ボーナスゲーム +1回'), findsOneWidget);
    expect(find.text('あと 2 回遊べます'), findsOneWidget);
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_earn_notice_test.dart`
Expected: FAIL — `BonusEarnNotice` が未定義

- [ ] **Step 3: `_BonusUnlockNotice` を置き換える**

`lib/ui/home_screen.dart` の `_BonusUnlockNotice` を削除し、次を追加する。
**private ではなく public にする**（テストから直接組み立てて検査するため。
`_BonusEntry` などは画面の中でしか意味を持たないので private のままでよい）。

```dart
/// タイムアタックのリザルトに出す、ボーナスゲーム獲得の告知。
///
/// **チケットの状態ではなく「この勝負で増えたか」で出す。** 回数制では
/// 勝負の前から回数が残っていることがあり、状態だけを見ると 4 問しか
/// クリアしていない勝負でも告知が出てしまう（仕様 §5）。
///
/// [earnedPlaysLeft] は、この勝負で獲得できたときに残り回数が入り、
/// 獲得できなかった（5 問未満、または今日の上限に達していた）ときは
/// null のまま。`onFinished` が非同期に `earn` を終えてから値が入るので、
/// 告知は後から現れる。
class BonusEarnNotice extends StatelessWidget {
  final ValueListenable<int?> earnedPlaysLeft;

  const BonusEarnNotice({super.key, required this.earnedPlaysLeft});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: earnedPlaysLeft,
      builder: (context, left, _) {
        if (left == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ボーナスゲーム +1回',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text('あと $left 回遊べます', style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
```

`import 'package:flutter/foundation.dart' show kIsWeb;` を
`show kIsWeb, ValueListenable;` に変える。

- [ ] **Step 4: `_startTimeAttack` を配線する**

`coordinator` と `bonus` を解決している行の後に追加する。

```dart
    // この勝負で獲得できたかを告知へ渡す。チケットの状態を見ると、
    // 勝負の前から残っていた回数まで「獲得した」ことになってしまう。
    final earnedPlaysLeft = ValueNotifier<int?>(null);
```

`onFinished` を置き換える。

```dart
              onFinished: (score) async {
                if (score < kBonusUnlockClears) return;
                final today = bonusDateKey(DateTime.now());
                if (!await bonus.earn(today)) return;
                earnedPlaysLeft.value = bonus.ticket.playsLeft(today);
              },
```

`resultNotice` を置き換える。

```dart
              resultNotice: BonusEarnNotice(earnedPlaysLeft: earnedPlaysLeft),
```

`.then((_) => session.dispose())` を置き換える。

```dart
        .then((_) {
          session.dispose();
          earnedPlaysLeft.dispose();
        });
```

- [ ] **Step 5: `test/ui/bonus_unlock_test.dart` を直す**

このファイルは `repo.startGame` と旧 API を使っている。次のように直す。

- `expect(await repo.earn(today()), isTrue)` はそのまま通る
- `repo.ticket.isAvailable(today())` もそのまま通る
- 「その日すでに遊んでいれば 5 問でも解禁しない」というテストは
  **仕様上まさに逆になった**（回数制では獲得できる）。
  「上限まで獲得済みなら増えない」に**置き換える**こと。

```dart
    test('今日の上限まで獲得済みなら増えない', () async {
      final repo = await loadedRepo();
      for (var i = 0; i < kBonusPlaysPerDay; i++) {
        expect(await repo.earn(today()), isTrue);
      }
      expect(await repo.earn(today()), isFalse);
      expect(repo.ticket.earned, kBonusPlaysPerDay);
    });
```

`ResultScreen` の `notice` を検査しているテストはそのまま通る
（`notice` は任意の Widget を受けるので `BonusEarnNotice` に変えても
影響しない）。

- [ ] **Step 6: テストが通ることを確認**

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_earn_notice_test.dart test/ui/bonus_unlock_test.dart`
Expected: PASS

- [ ] **Step 7: 告知が状態ではなく獲得で出ていることを確認する**

`onFinished` の `if (!await bonus.earn(today)) return;` を
`await bonus.earn(today);` に変える（＝増えなくても告知を出す）。

Run: `C:/flutter/bin/flutter.bat test test/ui/bonus_earn_notice_test.dart`
Expected: このテストは `BonusEarnNotice` を直接組むので**落ちない**。
**その場合、`_startTimeAttack` の配線を検査するテストが無いということ
なので、`HomeScreen` 経由で「上限に達している状態で 5 問クリアしても
告知が出ない」ことを見るテストを足すこと。** 追加したら、この変更で
落ちることを確認してから元に戻す。

- [ ] **Step 8: 全体のテストを走らせる**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass

- [ ] **Step 9: コミット**

```bash
git add lib/ui/home_screen.dart test/ui/bonus_earn_notice_test.dart test/ui/bonus_unlock_test.dart
git commit -m "feat(bonus): announce the play earned by this run, with the count left"
```

---

## 完了時の検証

- [ ] **1. テスト全体**

Run: `C:/flutter/bin/flutter.bat test`
Expected: all pass

- [ ] **2. アナライザ（ASCII パスのコピーで）**

```bash
rm -rf /c/Temp/m10plays && mkdir -p /c/Temp/m10plays
cd "C:/Users/e-yak/OneDrive/ドキュメント/nanaumi/MAKE10" && git archive HEAD | tar -x -C /c/Temp/m10plays
cd /c/Temp/m10plays && C:/flutter/bin/flutter.bat pub get && C:/flutter/bin/flutter.bat analyze
```

Expected: `No issues found!`。終わったら `rm -rf /c/Temp/m10plays`。

- [ ] **3. Web ビルド**

```bash
C:/flutter/bin/flutter.bat build web --no-tree-shake-icons; echo "exit=$?"
```

Expected: exit=0。**パイプに通さないこと**（非ゼロの終了コードが隠れる）。

- [ ] **4. 広告・課金プラグインが混入していないこと**

```bash
grep -c "google_mobile_ads\|in_app_purchase" build/web/main.dart.js || echo "0 matches (expected)"
```

Expected: 0 matches

- [ ] **5. ブランチの状態**

```bash
git status --porcelain
git log --oneline main..feat/bonus-plays-per-day
```

Expected: 作業ツリーがクリーン。
