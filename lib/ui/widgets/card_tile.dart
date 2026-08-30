import 'package:flutter/material.dart';

import '../../domain/board.dart';

/// 盤面の 1 枚。選択中とヒント強調で見た目を変える。
class CardTile extends StatelessWidget {
  final CardItem card;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  const CardTile({
    super.key,
    required this.card,
    required this.selected,
    required this.highlighted,
    required this.onTap,
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

    return Semantics(
      button: true,
      label: 'カード ${card.value}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 88,
          height: 112,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted ? scheme.tertiary : Colors.transparent,
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
