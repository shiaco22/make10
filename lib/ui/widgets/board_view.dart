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
