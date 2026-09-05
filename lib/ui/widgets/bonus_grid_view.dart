import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/bonus/bonus_grid.dart';

/// 1 手ぶんのアニメーション全体(消滅 120ms + 落下 180ms、仕様 §4.2)。
///
/// 消滅・落下を別々の [Duration] 定数として持たず、1 本の
/// [AnimationController] の進み具合(0.0〜1.0)を [_kVanishFraction] で
/// 割って 2 段階を区切っている。個別の Duration 定数は実際どこからも
/// 参照されない飾りになってしまう(analyzer の unused_element で検出済み)
/// ため、使う側の値だけを残す。
const Duration _kMoveDuration = Duration(milliseconds: 300);

/// 全体に占める消滅の割合。落下はこの後から始まる(重ねない、仕様 §4.2)。
/// 消滅 120ms / 全体 300ms を約分した値。
const double _kVanishFraction = 120 / 300;

/// 5×5 の盤面。
///
/// **一辺は必ず実際の制約から計算する。** マスの寸法を固定値で組むと
/// 狭い画面(320pt 幅)で溢れ、しかも Wrap のような溢れても黙る配置では
/// テストにも引っかからない。既存 GameScreen で、固定サイズのカードが
/// 2 行に折り返して 4 枚目が押せなくなった不具合がそれだった。
///
/// ここでは [LayoutBuilder] で得た制約の短辺から一辺を決め、[Column] と
/// [Row] で組む。計算を誤れば溢れて RenderFlex のエラーになる — 黙って
/// 壊れるより、はっきり落ちる方を選ぶ。
///
/// **描くのは常に現在の論理盤面。** アニメーションはその上の装飾に過ぎず、
/// 論理状態(スコア・盤面)はアニメーションを待たない(仕様 §4.1)。落ちて
/// きたマスは [Transform.translate] で「元いた位置」から定位置へ寄せて
/// 描き、消えたマスだけを別レイヤーの幽霊として重ねる。[Transform] は
/// レイアウトに影響しないので、320pt で溢れたら今までどおり RenderFlex が
/// 声を上げる(`Stack` + `Positioned` に土台を組み替えるとこの安全網を
/// 失うので、そちらへは寄せない)。
class BonusGridView extends StatefulWidget {
  final BonusGrid grid;
  final void Function(int index) onTapCell;

  /// 直近の手。アニメーションの内容はここから取る。null なら静止して描く。
  final BonusMerge? lastMerge;

  /// 手が進んだことを見分けるための通し番号([BonusSession.moveCount])。
  /// これが変わったらアニメーションを頭から再生する。
  final int moveSerial;

  const BonusGridView({
    super.key,
    required this.grid,
    required this.onTapCell,
    this.lastMerge,
    this.moveSerial = 0,
  });

  @override
  State<BonusGridView> createState() => _BonusGridViewState();
}

class _BonusGridViewState extends State<BonusGridView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kMoveDuration,
  );

  /// アニメーションに使う手。[widget.lastMerge] をそのまま見ないのは、
  /// 再生の途中で次の手が来たときに、いま再生中の手を最後まで持っていなくて
  /// よいから — 新しい手が来たら即座に差し替える(仕様 §4.1: 論理状態は
  /// アニメーションを待たない。連打で手が落ちてはいけない)。
  BonusMerge? _playing;

  @override
  void didUpdateWidget(covariant BonusGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moveSerial == oldWidget.moveSerial) return;
    // 手が進んだ。再生中でも構わず頭から差し替える。論理盤面([widget.grid])
    // は呼び出し側で既に新しいものになっているので、表示が一瞬飛んでも
    // 状態はずれない。
    _playing = widget.lastMerge;
    if (_reduceMotion) {
      _controller.value = 1.0;
    } else {
      _controller.forward(from: 0);
    }
  }

  /// OS のアニメーション減量設定。[didUpdateWidget] は State が
  /// mount された後にしか呼ばれないため、この時点で `context` から
  /// [MediaQuery] を読むのは安全(`initState` から読むのとは違い、
  /// 依存関係の登録を禁止する制約は無い)。
  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 添字 [i] の左上の座標。
  Offset _positionOf(int i, double cell) => Offset(
        (i % kBonusSize) * cell,
        (i ~/ kBonusSize) * cell,
      );

  /// 添字 [i] のマスを、いまどれだけずらして描くか。
  Offset _offsetFor(int i, double cell, double fallT) {
    final merge = _playing;
    if (merge == null || fallT >= 1.0) return Offset.zero;

    for (final entry in merge.fallenCells.entries) {
      if (entry.value != i) continue;
      final from = _positionOf(entry.key, cell);
      final to = _positionOf(i, cell);
      return (from - to) * (1 - fallT);
    }
    if (merge.spawnedCells.contains(i)) {
      // 盤面の上から滑り込ませる。**行の深さに関わらず、常に高々 1 マス分
      // だけ高い位置から落とす。** 「行が下ほど長く落とす(行数に比例)」案
      // もあったが、5 マス連結が縦一列に並ぶと列がまるごと空になり、
      // 最下段(5 行目)のマスが最上段の 5 倍の距離を同じ 180ms で移動する
      // ことになる — easeOut と相まって、他の(短い距離しか落ちない)マスを
      // 追い越すように速く見え、浮いて見える。1 マス固定なら、どの行に
      // 落ちても見た目の速さが揃う。
      //
      // **0 行目は頭打ちにする(1 マスではなく 0 マス)。** 0 行目は盤面の
      // 最上段なので、そこへ 1 マス分の頭出しをすると盤面の外(Y < 0)へ
      // はみ出す。盤面の Stack はそこで描画が終わる矩形そのものなので、
      // はみ出した点は Column/Row のヒットテストに一切届かず、アニメー
      // ション中にそのマスをタップできなくなる — 見た目のバグに留まらず
      // 「アニメーション中も全マスがタップできる」という要件(仕様 §4.1)
      // を壊す実測済みの不具合だった。
      final row = i ~/ kBonusSize;
      final headstartRows = row == 0 ? 0 : 1;
      return Offset(0, -cell * headstartRows * (1 - fallT));
    }
    return Offset.zero;
  }

  /// 幽霊に描く数字。この手で消えたマスは連結成分(同じ値)なので、
  /// まとめた数字は 1 つに決まる — [BonusGrid.tap] の `component` は
  /// `componentAt(index)` で求めた、タップ地点と同じ値が連結した集合。
  int _ghostValue(int i) => _playing?.mergedValue ?? 1;

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

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final vanishT = (t / _kVanishFraction).clamp(0.0, 1.0);
            final fallT = Curves.easeOut.transform(
              ((t - _kVanishFraction) / (1 - _kVanishFraction))
                  .clamp(0.0, 1.0),
            );

            return SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  // 土台は常に現在の論理盤面。Transform はレイアウトに
                  // 影響しないので、寸法を誤れば今までどおり RenderFlex が
                  // 溢れて声を上げる。
                  Column(
                    children: [
                      for (var row = 0; row < kBonusSize; row++)
                        Row(
                          children: [
                            for (var col = 0; col < kBonusSize; col++)
                              Transform.translate(
                                offset: _offsetFor(
                                    row * kBonusSize + col, cell, fallT),
                                child: BonusCellTile(
                                  key: ValueKey(
                                      'bonus-cell-${row * kBonusSize + col}'),
                                  value: widget.grid.valueAt(row, col),
                                  size: cell,
                                  onTap: () => widget
                                      .onTapCell(row * kBonusSize + col),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  // 消えたマスの幽霊。タップを奪わないよう IgnorePointer で
                  // 包む。
                  //
                  // `Positioned.fill` で包み、盤面いっぱいの矩形制約を
                  // 明示的に与える。このレイヤーの子は `Positioned` しか
                  // 持たないため、`Positioned.fill` を外して裸のまま外側の
                  // `Stack` に置いても、**この Flutter 版では** 実際には
                  // 潰れない(RenderStack は非配置の子を 1 つも持たない場合、
                  // 受け取った制約の上限にそのまま広がる —
                  // `RenderStack._computeSize` の `else { size =
                  // constraints.biggest; }` の分岐。実際に外して
                  // test/ui/widgets/bonus_animation_test.dart を走らせても
                  // 幽霊は変わらず描けたままだった)。それでも明示的に
                  // `Positioned.fill` で包んでおくのは、この「非配置の子が
                  // 無ければ広がる」という実装詳細に依存しないための保険 --
                  // 将来ここへ非配置の子(例えば読み込み中の別表示)を
                  // 1 つでも足すと、その子だけがサイズを決める側に回り、
                  // 幽霊レイヤー全体の寸法が変わってしまう。
                  if (_playing != null && vanishT < 1.0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Stack(
                          children: [
                            for (final i in _playing!.removedCells)
                              Positioned(
                                left: _positionOf(i, cell).dx,
                                top: _positionOf(i, cell).dy,
                                child: Opacity(
                                  opacity: 1 - vanishT,
                                  child: Transform.scale(
                                    scale: 1 - vanishT * 0.6,
                                    child: BonusCellTile(
                                      value: _ghostValue(i),
                                      size: cell,
                                      onTap: () {},
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
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
