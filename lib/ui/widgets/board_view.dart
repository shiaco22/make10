import 'package:flutter/material.dart';

import '../../domain/board.dart';
import 'card_tile.dart';

/// 盤面のカードを折り返しつつ中央寄せで並べる。
class BoardView extends StatelessWidget {
  final List<CardItem> cards;
  final int? selectedId;
  final Set<int> highlightedIds;
  final void Function(int id) onTapCard;

  const BoardView({
    super.key,
    required this.cards,
    required this.selectedId,
    required this.highlightedIds,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // タブレットでカードが散らばらないよう盤面の幅を制限する。
        constraints: const BoxConstraints(maxWidth: 420),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
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
              ),
          ],
        ),
      ),
    );
  }
}
