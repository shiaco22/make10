import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus_ticket.dart';

void main() {
  group('bonusDateKey', () {
    test('yyyy-MM-dd に整形する', () {
      expect(bonusDateKey(DateTime(2026, 9, 3)), '2026-09-03');
      expect(bonusDateKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(bonusDateKey(DateTime(2026, 1, 1, 23, 59, 59)), '2026-01-01');
    });

    test('日付が変わる瞬間で切り替わる', () {
      expect(bonusDateKey(DateTime(2026, 9, 3, 23, 59, 59)), '2026-09-03');
      expect(bonusDateKey(DateTime(2026, 9, 4, 0, 0, 0)), '2026-09-04');
    });
  });

  group('解禁条件', () {
    test('5 問が必要', () {
      expect(kBonusUnlockClears, 5);
    });
  });

  group('earn / isAvailable', () {
    test('初期状態では遊べない', () {
      final ticket = BonusTicket();
      expect(ticket.isAvailable('2026-09-03'), isFalse);
    });

    test('earn すると遊べるようになる', () {
      final ticket = BonusTicket();
      expect(ticket.earn('2026-09-03'), isTrue);
      expect(ticket.isAvailable('2026-09-03'), isTrue);
    });

    test('同じ日の 2 回目の earn は何も変えない', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      expect(ticket.earn('2026-09-03'), isFalse,
          reason: '2 回目の earn が「新しく解禁した」と報告している');
      expect(ticket.isAvailable('2026-09-03'), isTrue);
    });

    test('遊んだ後は同じ日にもう遊べない', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      ticket.consume('2026-09-03');
      expect(ticket.isAvailable('2026-09-03'), isFalse);
    });

    test('遊んだ後に 5 問クリアしても権利は復活しない', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      ticket.consume('2026-09-03');
      expect(ticket.earn('2026-09-03'), isFalse);
      expect(ticket.isAvailable('2026-09-03'), isFalse,
          reason: '1 日 1 回の制限が破れている');
    });
  });

  group('日付をまたぐ', () {
    test('繰り越さない（今日とった権利は今日のもの）', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      expect(ticket.isAvailable('2026-09-04'), isFalse,
          reason: '前日の権利が翌日に残っている');
    });

    test('翌日はまた解禁できる', () {
      final ticket = BonusTicket();
      ticket.earn('2026-09-03');
      ticket.consume('2026-09-03');
      expect(ticket.earn('2026-09-04'), isTrue);
      expect(ticket.isAvailable('2026-09-04'), isTrue);
    });

    test('前日に遊んでいても翌日の解禁を邪魔しない', () {
      final ticket = BonusTicket(unlockedOn: '2026-09-03', playedOn: '2026-09-03');
      expect(ticket.earn('2026-09-04'), isTrue);
      expect(ticket.isAvailable('2026-09-04'), isTrue);
    });
  });

  group('earn の playedOn チェックが本当に効いているか', () {
    // 上のテストだけでは、earn の「その日すでに遊んでいれば何もしない」の
    // 分岐が実際に効いているとは限らない。consume は今まで常に直前の
    // earn と同じ today で呼ばれているため、その分岐を削っても
    // `_unlockedOn == today` の判定だけで同じ結果になり、上のテストは
    // 全部通ってしまう(実際に削って確認した)。unlockedOn が today に
    // 更新される前に playedOn だけ today になる状態
    // (isAvailable の判定から consume までの間に日付が変わる、といった
    // 競合で起こりうる)を作り、playedOn の判定を単独で検証する。
    test('unlockedOn が古い日のままでも、today に既に遊んでいれば earn できない', () {
      final ticket =
          BonusTicket(unlockedOn: '2026-09-03', playedOn: '2026-09-04');
      expect(ticket.earn('2026-09-04'), isFalse,
          reason: 'unlockedOn だけを見て「today ではない」と誤判定している');
      expect(ticket.isAvailable('2026-09-04'), isFalse);
    });
  });

  group('復元', () {
    test('保存した値から状態を復元できる', () {
      final ticket = BonusTicket(unlockedOn: '2026-09-03', playedOn: null);
      expect(ticket.isAvailable('2026-09-03'), isTrue);
      expect(ticket.unlockedOn, '2026-09-03');
      expect(ticket.playedOn, isNull);
    });
  });
}
