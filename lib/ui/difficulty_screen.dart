import 'package:flutter/material.dart';

import '../domain/difficulty.dart';

class DifficultyScreen extends StatelessWidget {
  final String title;
  final void Function(Difficulty) onSelected;

  const DifficultyScreen({
    super.key,
    required this.title,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final difficulty in Difficulty.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 220,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => onSelected(difficulty),
                    child: Text(difficulty.label),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
