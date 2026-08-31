import 'package:flutter/material.dart';

import '../../domain/board.dart';
import 'card_tile.dart';

/// 盤面のカードを中央寄せで 1 行に並べる。
///
/// カードのサイズは [LayoutBuilder] で得られる実際の余白（幅・高さ）から
/// 逆算する。幅方向は「カード枚数 × 間隔」から、高さ方向は 88:112 の
/// 縦横比から、それぞれ「1 行に収まる最大サイズ」を求め、小さい方を採る。
/// [CardTile.baseWidth] / [CardTile.baseHeight] (88×112) を上限とすることで、
/// タブレットのような余白の多い画面でもカードが拡大しすぎないようにする
/// （下の [ConstrainedBox] の maxWidth: 420 と合わせて機能する）。
///
/// 折り返し (Wrap) ではなく常に 1 行の Row で並べる。カードのサイズは
/// 「1 行に収まる」ことを前提に逆算しているため、折り返し判定に頼る必要が
/// なく、万一サイズ計算がずれた場合も Wrap のように無警告で 2 行目へ
/// 逃げず、素直にオーバーフローとして検出できる。
class BoardView extends StatelessWidget {
  final List<CardItem> cards;
  final int? selectedId;
  final Set<int> highlightedIds;
  final void Function(int id) onTapCard;

  /// 直近で拒否された合成の対象カード id。null なら震えているカードはない。
  final int? shakeCardId;

  /// [shakeCardId] のカードへ渡す震えの合図。[GameSession.rejectionSeq] を
  /// そのまま渡す想定で、値そのものに意味はなく変化だけを見る。
  final Object? shakeSignal;

  static const double _spacing = 12;
  static const double _aspect = CardTile.baseHeight / CardTile.baseWidth;

  const BoardView({
    super.key,
    required this.cards,
    required this.selectedId,
    required this.highlightedIds,
    required this.onTapCard,
    this.shakeCardId,
    this.shakeSignal,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // タブレットでカードが散らばらないよう盤面の幅を制限する。
        constraints: const BoxConstraints(maxWidth: 420),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = _cardSizeFor(constraints, cards.length);
            final tiles = <Widget>[];
            for (var i = 0; i < cards.length; i++) {
              if (i > 0) tiles.add(const SizedBox(width: _spacing));
              final card = cards[i];
              tiles.add(
                CardTile(
                  // マージのたびに 2 枚が消えて 1 枚増えるため、生存カードは
                  // 前方のインデックスへ詰まる。id で key を付けないと
                  // Flutter が位置で要素を再利用し、以前そこにあった別カード
                  // の AnimatedContainer アニメーション状態を引き継いでしまう
                  // (本来アニメーションしないはずの場面で色がフェードする)。
                  key: ValueKey(card.id),
                  card: card,
                  selected: card.id == selectedId,
                  highlighted: highlightedIds.contains(card.id),
                  onTap: () => onTapCard(card.id),
                  width: size.width,
                  height: size.height,
                  shakeSignal: card.id == shakeCardId ? shakeSignal : null,
                ),
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: tiles,
            );
          },
        ),
      ),
    );
  }

  /// [constraints] の余白に [count] 枚のカードを 1 行で収める最大サイズを
  /// 求める。[CardTile.baseWidth] / [CardTile.baseHeight] (88×112) を上限に、
  /// 幅から逆算したサイズと高さから逆算したサイズの小さい方を採る。
  Size _cardSizeFor(BoxConstraints constraints, int count) {
    if (count <= 0) {
      return const Size(CardTile.baseWidth, CardTile.baseHeight);
    }

    final totalSpacing = _spacing * (count - 1);
    var width = (constraints.maxWidth - totalSpacing) / count;

    if (constraints.maxHeight.isFinite) {
      final widthFromHeight = constraints.maxHeight / _aspect;
      if (widthFromHeight < width) width = widthFromHeight;
    }

    width = width.clamp(0.0, CardTile.baseWidth);
    return Size(width, width * _aspect);
  }
}
