import 'package:flutter/material.dart';

import '../../domain/board.dart';
import 'card_tile.dart';
import 'responsive.dart';

/// 盤面のカードを中央寄せで 1 行に並べる。
///
/// カードのサイズは [LayoutBuilder] で得られる実際の余白（幅・高さ）から
/// 逆算する。幅方向は「カード枚数 × 間隔」から、高さ方向は 88:112 の
/// 縦横比から、それぞれ「1 行に収まる最大サイズ」を求め、小さい方を採る。
/// その上限は電話では [CardTile.baseWidth] / [CardTile.baseHeight]
/// (88×112) そのものだが、タブレットでは [uiScale] に応じてこの上限自体を
/// 拡大する (build 内の `cardMaxSize`)。上限が伸びるおかげで、余白の多い
/// タブレットの画面ではカード自身も大きくなる（[_baseBoardMaxWidth] から
/// 求まる盤面幅の上限とあわせて機能する -- そちらも同じ拡大率で伸びるので
/// 「4 枚が 1 つの塊に見える」意図は保ったまま、塊自体が大きくなる）。
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

  /// 電話サイズでの、カード間隔・盤面幅上限。タブレットでは [uiScale] を
  /// 掛けて拡大する。
  static const double _baseSpacing = 12;
  static const double _baseBoardMaxWidth = 420;

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
    final scale = uiScale(context);
    final spacing = _baseSpacing * scale;
    final cardMaxSize = Size(
      CardTile.baseWidth * scale,
      CardTile.baseHeight * scale,
    );

    return Center(
      child: ConstrainedBox(
        // タブレットでカードが散らばらないよう盤面の幅を制限する。この
        // 上限自体も scale で伸びるので、電話では今日どおり 420 のまま、
        // タブレットではカードの拡大に合わせて塊全体も大きくなる。
        constraints: BoxConstraints(maxWidth: _baseBoardMaxWidth * scale),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size =
                _cardSizeFor(constraints, cards.length, cardMaxSize, spacing);
            final tiles = <Widget>[];
            for (var i = 0; i < cards.length; i++) {
              if (i > 0) tiles.add(SizedBox(width: spacing));
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
                  scale: scale,
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
  /// 求める。[cardMaxSize] を上限に、幅から逆算したサイズと高さから逆算
  /// したサイズの小さい方を採る。カード間の間隔は [spacing]。
  Size _cardSizeFor(
    BoxConstraints constraints,
    int count,
    Size cardMaxSize,
    double spacing,
  ) {
    if (count <= 0) {
      return cardMaxSize;
    }

    final totalSpacing = spacing * (count - 1);
    var width = (constraints.maxWidth - totalSpacing) / count;

    if (constraints.maxHeight.isFinite) {
      final widthFromHeight = constraints.maxHeight / _aspect;
      if (widthFromHeight < width) width = widthFromHeight;
    }

    width = width.clamp(0.0, cardMaxSize.width);
    return Size(width, width * _aspect);
  }
}
