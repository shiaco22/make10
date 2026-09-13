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
