import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:make10/domain/bonus/bonus_grid.dart';
import 'package:make10/ui/app.dart';
import 'package:make10/ui/widgets/bonus_grid_view.dart';

BonusGrid gridOf(List<List<int>> rows) =>
    BonusGrid.of([for (final row in rows) ...row]);

BonusGrid distinctGrid() => gridOf([
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 1],
      [2, 3, 4, 5, 6],
      [7, 8, 9, 1, 2],
      [3, 4, 5, 6, 7],
    ]);

Future<void> pumpGrid(
  WidgetTester tester,
  BonusGrid grid, {
  required void Function(int) onTapCell,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: BonusGridView(grid: grid, onTapCell: onTapCell)),
      ),
    ),
  );
}

/// WCAG relative luminance (sRGB) -- same formula as
/// `test/ui/widgets/card_tile_test.dart`, factored so the CIE L*a*b*
/// conversion below can reuse the identical gamma decode.
double _linearChannel(double c) {
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  return 0.2126 * _linearChannel(color.r) +
      0.7152 * _linearChannel(color.g) +
      0.0722 * _linearChannel(color.b);
}

/// WCAG contrast ratio between two colors (1.0 = indistinguishable, 21.0 = max).
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a) + 0.05;
  final lb = _relativeLuminance(b) + 0.05;
  return la > lb ? la / lb : lb / la;
}

/// [color] in CIE L*a*b* (D65 white point), as `[L*, a*, b*]`.
List<double> _labOf(Color color) {
  final r = _linearChannel(color.r);
  final g = _linearChannel(color.g);
  final b = _linearChannel(color.b);

  // Linear sRGB -> CIE XYZ (D65).
  final x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
  final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
  final z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;

  const xn = 0.95047;
  const yn = 1.0;
  const zn = 1.08883;
  double f(double t) {
    const delta = 6.0 / 29.0;
    return t > delta * delta * delta
        ? math.pow(t, 1 / 3).toDouble()
        : t / (3 * delta * delta) + 4.0 / 29.0;
  }

  final fx = f(x / xn);
  final fy = f(y / yn);
  final fz = f(z / zn);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

/// CIE76 perceptual color difference (Delta E): Euclidean distance in
/// CIE L*a*b*. Folds hue, saturation *and* lightness differences into one
/// number, so a palette that collapses towards a few similar shades (by
/// hue, by saturation, or by lightness) shows up as a small value here even
/// when it might not on any single channel. Rule of thumb: dE < 2 needs a
/// side-by-side comparison to notice, 2-10 is noticeable at a glance, 10+
/// reads as a plainly different color.
double _deltaE76(Color a, Color b) {
  final labA = _labOf(a);
  final labB = _labOf(b);
  var sumSq = 0.0;
  for (var i = 0; i < 3; i++) {
    final d = labA[i] - labB[i];
    sumSq += d * d;
  }
  return math.sqrt(sumSq);
}

/// The bar for "clearly a different color" used below for both the
/// adjacent-value check and the value-10 check. Chosen well above the
/// noticeable-at-a-glance range (2-10) so a genuine regression (palette
/// collapsing toward a handful of shades) fails loudly while leaving
/// engineering headroom: this palette's actual minimum is 23 (adjacent
/// pairs) and 64 (value 10 vs. everything else).
const double _kClearlyDistinctDeltaE = 15.0;

Widget wrapTile(Widget child, ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );

Color fillOf(WidgetTester tester, Finder of) => tester
    .widget<Material>(
      find.descendant(of: of, matching: find.byType(Material)),
    )
    .color!;

Color textColorOf(WidgetTester tester, Finder of) => tester
    .widget<Text>(
      find.descendant(of: of, matching: find.byType(Text)),
    )
    .style!
    .color!;

/// The page's actually-painted background. `find.byType(Scaffold)`
/// descendants include both the Scaffold's own background [Material] *and*
/// whatever [Material] the cell itself paints (it sits inside the
/// Scaffold's body), so -- as in `card_tile_test.dart` -- take the first
/// match, which resolves to the Scaffold's own background.
Color pageColorOf(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(of: find.byType(Scaffold), matching: find.byType(Material))
          .first,
    )
    .color!;

void main() {
  testWidgets('25 マスすべてを描く', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {});
    // 値 9 は 2 箇所、値 1 は 3 箇所にある。総数で数える。
    expect(find.byType(BonusCellTile), findsNWidgets(kBonusCells));
  });

  testWidgets('マスの数字を表示する', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {});
    expect(find.text('7'), findsNWidgets(3));
    expect(find.text('8'), findsNWidgets(2));
  });

  testWidgets('タップした添字を通知する', (tester) async {
    final tapped = <int>[];
    await pumpGrid(tester, distinctGrid(), onTapCell: tapped.add);
    await tester.tap(find.byKey(const ValueKey('bonus-cell-0')));
    await tester.tap(find.byKey(const ValueKey('bonus-cell-24')));
    await tester.tap(find.byKey(const ValueKey('bonus-cell-12')));
    expect(tapped, [0, 24, 12]);
  });

  testWidgets('320pt 幅でも 25 マスすべてがタップできる', (tester) async {
    // 既存 GameScreen で、固定サイズのカードが狭い画面で 2 行に折り返し、
    // 4 枚目がヒットテストに反応しなくなった不具合と同じ罠を防ぐ。
    // Wrap は溢れてもエラーを出さないので、テストで押せることを直接見る。
    final tapped = <int>[];
    await pumpGrid(
      tester,
      distinctGrid(),
      onTapCell: tapped.add,
      size: const Size(320, 480),
    );
    expect(tester.takeException(), isNull);
    for (var i = 0; i < kBonusCells; i++) {
      await tester.tap(find.byKey(ValueKey('bonus-cell-$i')));
    }
    expect(tapped, [for (var i = 0; i < kBonusCells; i++) i],
        reason: '320pt 幅で押せないマスがある');
  });

  testWidgets('盤面は正方形で、横に溢れない', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {},
        size: const Size(320, 480));
    final box = tester.getSize(find.byType(BonusGridView));
    expect(box.width, closeTo(box.height, 1.0), reason: '盤面が正方形でない');
    expect(box.width, lessThanOrEqualTo(320));
  });

  testWidgets('横長の画面でも高さに収まる', (tester) async {
    await pumpGrid(tester, distinctGrid(), onTapCell: (_) {},
        size: const Size(800, 360));
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byType(BonusGridView));
    expect(box.height, lessThanOrEqualTo(360));
  });

  // 値 1..10 の塗りとテキスト色の実測コントラスト。プレイヤーが数字を
  // 読めるかどうかの床(WCAG 4.5:1)を、実際にレンダリングされた色から
  // 検証する -- パレットの数式(HSL の彩度/明度や primary の実値)を
  // ハードコードで再現するのではなく、ウィジェットが実際に描いた色を
  // 読み取って計算する。
  for (final entry in <String, ThemeData>{
    'light': Make10App.lightTheme,
    'dark': Make10App.darkTheme,
  }.entries) {
    testWidgets(
      '値 1〜10 のマスは自分の塗りに対し WCAG 4.5:1 以上を保つ (${entry.key})',
      (tester) async {
        final ratios = <int, double>{};
        for (var value = 1; value <= 10; value++) {
          await tester.pumpWidget(wrapTile(
            BonusCellTile(value: value, size: 100, onTap: () {}),
            entry.value,
          ));
          final fill = fillOf(tester, find.byType(BonusCellTile));
          final text = textColorOf(tester, find.byType(BonusCellTile));
          ratios[value] = _contrastRatio(fill, text);
        }
        // 常に(失敗時だけでなく)出力する -- `flutter test` の出力に
        // 実測比が必ず残るようにする。
        // ignore: avoid_print
        print(
          'bonus cell contrast ratios (${entry.key} theme): '
          '${[
            for (var v = 1; v <= 10; v++)
              '$v=${ratios[v]!.toStringAsFixed(3)}',
          ].join(' ')}',
        );
        for (var value = 1; value <= 10; value++) {
          expect(
            ratios[value],
            greaterThanOrEqualTo(4.5),
            reason: '値 $value のマス (${entry.key} テーマ) が WCAG 4.5:1 を'
                '満たさない: ${ratios[value]}',
          );
        }
      },
    );
  }

  // 隣接する値(n と n+1)は、色そのもので見分けが付くほど離れていな
  // ければならない -- 単なる非等価判定ではなく、色相・彩度・明度を
  // まとめて 1 つの数字にする知覚色差(CIE76 ΔE)で測る。値 1〜9 の塗りは
  // テーマに依存しないが、値 10 は scheme.primary を使うためテーマに
  // 依存する。9-10 のペアがどちらのテーマでも成立することを見るため、
  // 両テーマで確認する。
  for (final entry in <String, ThemeData>{
    'light': Make10App.lightTheme,
    'dark': Make10App.darkTheme,
  }.entries) {
    testWidgets(
      '隣接する値どうしの塗りは知覚的に区別できるほど離れている (${entry.key})',
      (tester) async {
        final fills = <int, Color>{};
        for (var value = 1; value <= 10; value++) {
          await tester.pumpWidget(wrapTile(
            BonusCellTile(value: value, size: 100, onTap: () {}),
            entry.value,
          ));
          fills[value] = fillOf(tester, find.byType(BonusCellTile));
        }
        for (var value = 1; value < 10; value++) {
          final de = _deltaE76(fills[value]!, fills[value + 1]!);
          // ignore: avoid_print
          print(
            'deltaE($value, ${value + 1}) (${entry.key}) = '
            '${de.toStringAsFixed(2)}',
          );
          expect(
            de,
            greaterThanOrEqualTo(_kClearlyDistinctDeltaE),
            reason: '値 $value と ${value + 1} の塗りが近すぎて色で区別'
                'できない (${entry.key} テーマ, ΔE=$de)',
          );
        }
      },
    );
  }

  // マスの塗りは、盤面が乗っている Scaffold の背景そのものと見分けが
  // 付かなければ、そもそも「マス」として見えない。CardTile がかつて
  // theme.cardColor(既定で colorScheme.surface)を塗りに使い、Scaffold
  // の背景と同色になって消えていた不具合と同じ穴を塞ぐ確認 --
  // 両テーマで、実際に描かれた Scaffold の背景色に対して測る。
  for (final entry in <String, ThemeData>{
    'light': Make10App.lightTheme,
    'dark': Make10App.darkTheme,
  }.entries) {
    testWidgets(
      'マスの塗りは Scaffold の背景と見分けが付く (${entry.key})',
      (tester) async {
        for (var value = 1; value <= 10; value++) {
          await tester.pumpWidget(wrapTile(
            BonusCellTile(value: value, size: 100, onTap: () {}),
            entry.value,
          ));
          final fill = fillOf(tester, find.byType(BonusCellTile));
          final pageColor = pageColorOf(tester);
          final ratio = _contrastRatio(fill, pageColor);
          expect(
            ratio,
            greaterThan(3.0),
            reason: '値 $value のマス (${entry.key} テーマ) の塗り $fill が'
                '背景 $pageColor と十分に区別できない: $ratio',
          );
        }
      },
    );
  }

  testWidgets('10 のマスが他と区別して描かれる', (tester) async {
    final cleared = gridOf([
      [kBonusTarget, 1, 2, 3, 4],
      [5, 6, 7, 8, 9],
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 1],
      [2, 3, 4, 5, 6],
    ]);
    await pumpGrid(tester, cleared, onTapCell: (_) {});
    expect(find.text('10'), findsOneWidget);

    // 単に "10" というテキストが存在するだけでは、他のマスと同じ色・
    // 同じ見た目でも通ってしまう(isTarget を常に false にする変異でも
    // 緑になる)。実際に塗り色が他の全マスと異なることと、その差が
    // 知覚的にもはっきりしていることの両方をピン留めする。
    final targetFill = fillOf(tester, find.byKey(const ValueKey('bonus-cell-0')));
    final otherFills = {
      for (var i = 1; i < kBonusCells; i++)
        fillOf(tester, find.byKey(ValueKey('bonus-cell-$i'))),
    };
    expect(
      otherFills.contains(targetFill),
      isFalse,
      reason: '10 のマスの塗り $targetFill が他のいずれかのマスと同じ色に'
          'なっている',
    );
    for (final fill in otherFills) {
      expect(
        _deltaE76(targetFill, fill),
        greaterThanOrEqualTo(_kClearlyDistinctDeltaE),
        reason: '10 のマスの塗り $targetFill が他のマスの塗り $fill と'
            '十分に離れていない',
      );
    }
  });
}
