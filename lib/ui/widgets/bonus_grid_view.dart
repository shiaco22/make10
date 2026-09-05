import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/bonus/bonus_grid.dart';

/// 5×5 の盤面。
///
/// **一辺は必ず実際の制約から計算する。** マスの寸法を固定値で組むと
/// 狭い画面（320pt 幅）で溢れ、しかも Wrap のような溢れても黙る配置では
/// テストにも引っかからない。既存 GameScreen で、固定サイズのカードが
/// 2 行に折り返して 4 枚目が押せなくなった不具合がそれだった。
///
/// ここでは [LayoutBuilder] で得た制約の短辺から一辺を決め、[Column] と
/// [Row] で組む。計算を誤れば溢れて RenderFlex のエラーになる — 黙って
/// 壊れるより、はっきり落ちる方を選ぶ。
class BonusGridView extends StatelessWidget {
  final BonusGrid grid;
  final void Function(int index) onTapCell;

  const BonusGridView({
    super.key,
    required this.grid,
    required this.onTapCell,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 制約が無限のときは MediaQuery に落とす。Center の中など、
        // 高さが無制限で渡ってくる配置があるため。
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final side = maxWidth < maxHeight ? maxWidth : maxHeight;
        final cell = side / kBonusSize;

        return SizedBox(
          width: side,
          height: side,
          child: Column(
            children: [
              for (var row = 0; row < kBonusSize; row++)
                Row(
                  children: [
                    for (var col = 0; col < kBonusSize; col++)
                      BonusCellTile(
                        key: ValueKey('bonus-cell-${row * kBonusSize + col}'),
                        value: grid.valueAt(row, col),
                        size: cell,
                        onTap: () => onTapCell(row * kBonusSize + col),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 色相の並びの段数(値 1..9 を割り当てる非達成マスの分)。
const int _kBonusHueSteps = 9;

/// 隣接する色相どうしの間隔。360 を [_kBonusHueSteps] で均等割りする。
const double _kBonusHueStep = 360.0 / _kBonusHueSteps;

/// 全色相共通の彩度。
const double _kBonusSaturation = 0.70;

/// 色相ごとの HSL 明度(値 1..9、`(value - 1) % 9` で引く)。
///
/// **HSL の明度を固定しない理由:** 彩度・明度を固定して色相だけ回すと、
/// 色相によって実際の見た目の明るさ(sRGB 相対輝度)が大きく変わる。
/// WCAG の相対輝度は G チャンネルが支配的な重み(0.7152)を持つため、
/// 同じ HSL 明度 0.55 でも黄緑(相対輝度 0.58)と青紫(0.15)では
/// 3.6 倍もの開きが出る。これが、白文字を常に使っていたときに値
/// 3〜6 のマスで数字がほぼ見えなくなっていた不具合の直接の原因だった
/// (実測コントラスト比 1.65〜1.94)。
///
/// 固定すべきは「HSL の明度」ではなく「結果の相対輝度」。ここでは
/// 色相ごとに、結果の相対輝度がおよそ 0.19 になるよう HSL 明度を
/// あらかじめ逆算して並べてある(逆算の方法は
/// `test/ui/widgets/bonus_grid_view_test.dart` 参照)。0.19 を選んだ根拠:
/// - [_kLuminanceReadableCrossover] のすぐ上にあり、[_readableTextColor]
///   が選ぶ黒文字との比は (0.19+0.05)/0.05 = 4.8 で WCAG 4.5:1 の床に
///   十分な余裕を残す。
/// - 実際のアプリのライトテーマの Scaffold 背景(相対輝度 ≈0.95)に
///   対して ≈4.16:1、ダークテーマ(≈0.0066)に対して ≈4.24:1 になり、
///   どちらも `CardTile` が境界線に使っている WCAG 1.4.11 の 3:1 の床を
///   はっきり超える(`test/ui/widgets/card_tile_test.dart` 参照)。
const List<double> _kBonusLightness = [
  0.5523, // 1 (hue   0°, 赤)
  0.3599, // 2 (hue  40°, 橙)
  0.3042, // 3 (hue  80°, 黄緑)
  0.3227, // 4 (hue 120°, 緑)
  0.3161, // 5 (hue 160°, 青緑)
  0.4082, // 6 (hue 200°, 空色)
  0.6562, // 7 (hue 240°, 青)
  0.5806, // 8 (hue 280°, 紫)
  0.5092, // 9 (hue 320°, ピンク)
];

/// WCAG 2.x の相対輝度(sRGB、ガンマ補正した各チャンネルを
/// 0.2126/0.7152/0.0722 で加重和する)。
double _relativeLuminance(Color color) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 相対輝度がこの値以下の塗りには白文字を、より大きい塗りには黒文字を
/// 選ぶと、**どんな塗り色に対しても** WCAG の 4.5:1 を割らない。
///
/// 導出: 白文字(輝度 1.0)の比は `1.05 / (L + 0.05)`、黒文字(輝度 0.0)
/// の比は `(L + 0.05) / 0.05`。前者が 4.5 を満たす範囲は `L <= 0.18333`、
/// 後者が満たす範囲は `L >= 0.175`。0.175 < 0.18333 なので 2 つの範囲は
/// [0, 1] 全体を隙間なく覆う(重なりは [0.175, 0.18333])。この重なりの
/// 中点(両条件がちょうど釣り合う点)が最悪ケースのコントラスト比を
/// 最大化する: `sqrt(1.05 * 0.05) - 0.05 ≈ 0.17913`。
const double _kLuminanceReadableCrossover = 0.17913;

/// [fill] の上に置いて WCAG 4.5:1 を満たすテキスト色(白 or 黒)。
Color _readableTextColor(Color fill) {
  return _relativeLuminance(fill) <= _kLuminanceReadableCrossover
      ? Colors.white
      : Colors.black;
}

/// 盤面の 1 マス。
class BonusCellTile extends StatelessWidget {
  final int value;
  final double size;
  final VoidCallback onTap;

  const BonusCellTile({
    super.key,
    required this.value,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 値そのものを色相に写す。プレイヤーは数字を読む前に色で同値の塊を
    // 見つけるので、隣接する値(n と n+1)がはっきり違う色になることが
    // 要点。彩度は固定し、10 段階を等間隔の色相に並べる(明度は
    // [_kBonusLightness] が色相ごとに変える -- 上のコメント参照)。
    //
    // `% _kBonusHueSteps` は int の `%` なので(Dart の int.% は除数が
    // 正なら常に非負を返す)value が 0 以下でも例外にならない。
    // kBonusEmpty(0)は本来プレイヤーには見えない内部状態だが、盤面が
    // 10 を作った直後の一瞬だけ空きマスと混在し得るため、ここで落ちない
    // ことを優先する。
    final isTarget = value >= kBonusTarget;
    final step = (value - 1) % _kBonusHueSteps;
    final hue = step * _kBonusHueStep;
    final fill = isTarget
        ? scheme.primary
        : HSLColor.fromAHSL(1.0, hue, _kBonusSaturation, _kBonusLightness[step])
            .toColor();
    final textColor = isTarget ? scheme.onPrimary : _readableTextColor(fill);

    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(size * 0.04),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(size * 0.14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(size * 0.14),
            child: Center(
              child: Text(
                '$value',
                style: TextStyle(
                  // マスの寸法から導く。固定値だと 320pt 幅で文字が
                  // マスに収まらない。
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
