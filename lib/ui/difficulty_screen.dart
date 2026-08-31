import 'package:flutter/material.dart';

import '../domain/difficulty.dart';
import 'widgets/responsive.dart';

/// 電話でのボタンの大きさ。タブレットでは [uiScale] を掛けて拡大する。
const double _kButtonWidth = 220;
const double _kButtonHeight = 56;

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
    // 電話 (scale == 1.0) では幅・高さともに今日と同じ 220x56 / style は
    // null のまま (FilledButton の見た目を一切変えない)。
    final scale = uiScale(context);
    final buttonStyle = scale > 1.0
        ? FilledButton.styleFrom(textStyle: TextStyle(fontSize: 18 * scale))
        : null;

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
                  width: _kButtonWidth * scale,
                  height: _kButtonHeight * scale,
                  child: FilledButton(
                    style: buttonStyle,
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
