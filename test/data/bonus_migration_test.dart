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

    test('日付をまたいだ獲得は新しい日として永続化される', () async {
      // BonusRepository.earn は BonusTicket.earn が true を返したときだけ
      // 保存する。日付が変わった直後の獲得は、内部でカウンタをリセットして
      // から 1 増やすため常に true になるが、それが実際に保存されることを
      // 確かめておく。ここが抜けると、再起動のたびに前日の日付へ戻り、
      // 今日分の獲得が消えて見える(仕様 §2.2 の「日付が変わったらリセット」
      // が永続化されない、という回帰)。
      setPrefs({
        'version': 2,
        'day': yesterday,
        'earned': kBonusPlaysPerDay,
        'played': kBonusPlaysPerDay,
      });
      final repo = await loaded();
      expect(await repo.earn(today), isTrue,
          reason: '日付が変わったのにリセットされていない');
      expect(repo.ticket.day, today);
      expect(repo.ticket.earned, 1);
      expect(repo.ticket.played, 0);

      final reloaded = await loaded();
      expect(reloaded.ticket.day, today,
          reason: '日替わりが保存されておらず、古い日付のまま復元された');
      expect(reloaded.ticket.earned, 1);
      expect(reloaded.ticket.played, 0);
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
