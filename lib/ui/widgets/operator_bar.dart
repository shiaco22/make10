import 'package:flutter/material.dart';

import '../../domain/operation.dart';

class OperatorBar extends StatelessWidget {
  final Op? selected;
  final void Function(Op op) onTap;

  const OperatorBar({super.key, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 4 個 x (64px + 左右 6px パディング) = 304px。iPhone SE 級の 320 幅では
    // 本体の Padding(16) を引くと 288px しか残らず、素の Row では右に
    // 16px はみ出す。FittedBox で「収まらない時だけ」縮小し、収まる幅
    // (例: 375px) ではそのままのサイズで描画する。
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final op in Op.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 64,
                height: 64,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: op == selected
                        ? scheme.primary
                        : scheme.secondaryContainer,
                    foregroundColor: op == selected
                        ? scheme.onPrimary
                        : scheme.onSecondaryContainer,
                  ),
                  onPressed: () => onTap(op),
                  child: Text(
                    opSymbol(op),
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
