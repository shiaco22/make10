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
    // 見つけるので、隣接する値（n と n+1）がはっきり違う色になることが
    // 要点。彩度と明度を固定して、10 段階を等間隔の色相に並べる。
    final isTarget = value >= kBonusTarget;
    final hue = (value - 1) * 34.0;
    final fill = isTarget
        ? scheme.primary
        : HSLColor.fromAHSL(1.0, hue % 360, 0.62, 0.55).toColor();

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
                  color: isTarget ? scheme.onPrimary : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
