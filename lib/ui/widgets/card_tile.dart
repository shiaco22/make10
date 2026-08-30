import 'package:flutter/material.dart';

import '../../domain/board.dart';

/// 盤面の 1 枚。選択中とヒント強調で見た目を変える。
///
/// サイズは呼び出し側（[BoardView]）が利用可能な余白から計算して渡す。
/// [baseWidth] × [baseHeight] (88×112) が既定値であり、同時に
/// BoardView 側での上限（タブレットで拡大しすぎない）としても使われる。
class CardTile extends StatelessWidget {
  final CardItem card;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final double width;
  final double height;

  /// カードの既定サイズ。88:112 の縦横比を保つ。
  static const double baseWidth = 88;
  static const double baseHeight = 112;

  const CardTile({
    super.key,
    required this.card,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    this.width = baseWidth,
    this.height = baseHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color background;
    final Color foreground;
    if (selected) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (highlighted) {
      background = scheme.tertiaryContainer;
      foreground = scheme.onTertiaryContainer;
    } else {
      // cardColor は Material のバージョン差に影響されない。
      // surfaceContainerHighest 等の新しいトークンは SDK 依存になるため使わない。
      background = theme.cardColor;
      foreground = scheme.onSurface;
    }

    final Color borderColor;
    if (selected && highlighted) {
      // 塗りは primary (選択中が優先) だが、Material 3 では primary と
      // tertiary はトーンが近くほぼ無彩色差になり得るため、実際に塗られる
      // primary に対して確実にコントラストが取れる onPrimary を使う。
      borderColor = scheme.onPrimary;
    } else if (highlighted) {
      borderColor = scheme.tertiary;
    } else {
      borderColor = Colors.transparent;
    }

    return Semantics(
      button: true,
      label: 'カード ${card.value}',
      // 付けないと内側の Text が生成する暗黙のラベルがマージされ、
      // 読み上げが「カード 9\n9」のように重複してしまう。
      excludeSemantics: true,
      // 上記で子孫の Semantics (InkWell 内のタップ操作を含む) を遮断する
      // ため、タップ操作はここで明示的に再提供する。
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: 3,
            ),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${card.value}',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
