import 'package:flutter/material.dart';

class ActionBar extends StatelessWidget {
  final bool canUndo;

  /// 盤面を編集する操作 (戻す/最初から/スキップ) を許すか。
  ///
  /// phase が playing でなくなったら (答えを見た後、あるいはクリア後) false
  /// にする。GameSession 側は戻す/最初から/スキップそれぞれで少しずつ違う
  /// ガードを持つが（例えば「戻す」はクリア直後の 1 手も戻せる）、
  /// ここでは「一度 playing を離れたら盤面はもういじれない」という単純な
  /// 方針に統一し、常に「次の問題へ」だけを次の一手として見せる
  /// （仕様 §3.3）。
  final bool interactionEnabled;

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
    required this.interactionEnabled,
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
          onPressed: (interactionEnabled && canUndo) ? onUndo : null,
          icon: const Icon(Icons.undo),
          label: const Text('戻す'),
        ),
        TextButton.icon(
          onPressed: (interactionEnabled && canUndo) ? onReset : null,
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
          onPressed: interactionEnabled ? onSkip : null,
          icon: const Icon(Icons.skip_next),
          label: const Text('スキップ'),
        ),
      ],
    );
  }
}
