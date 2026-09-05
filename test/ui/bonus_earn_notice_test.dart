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
