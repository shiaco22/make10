import 'package:flutter/material.dart';

class ActionBar extends StatelessWidget {
  final bool canUndo;

  /// タイムアタックでは false。ヒントと答えを押せなくする。
  final bool assistEnabled;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback onHint;
  final VoidCallback onAnswer;
  final VoidCallback onSkip;

  const ActionBar({
    super.key,
    required this.canUndo,
    required this.assistEnabled,
    required this.onUndo,
    required this.onReset,
    required this.onHint,
    required this.onAnswer,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo),
          label: const Text('戻す'),
        ),
        TextButton.icon(
          onPressed: canUndo ? onReset : null,
          icon: const Icon(Icons.refresh),
          label: const Text('最初から'),
        ),
        TextButton.icon(
          onPressed: assistEnabled ? onHint : null,
          icon: const Icon(Icons.lightbulb_outline),
          label: const Text('ヒント'),
        ),
        TextButton.icon(
          onPressed: assistEnabled ? onAnswer : null,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('答え'),
        ),
        TextButton.icon(
          onPressed: onSkip,
          icon: const Icon(Icons.skip_next),
          label: const Text('スキップ'),
        ),
      ],
    );
  }
}
