import 'package:flutter/material.dart';

import '../../domain/operation.dart';

class OperatorBar extends StatelessWidget {
  final Op? selected;
  final void Function(Op op) onTap;

  const OperatorBar({super.key, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
    );
  }
}
