import 'package:flutter/material.dart';

import '../../domain/operation.dart';
import 'responsive.dart';

class OperatorBar extends StatelessWidget {
  final Op? selected;

  /// ヒントがエスカレーション（式表示）まで進んだときの、その式の演算子。
  ///
  /// レベル 1（ハイライトのみ）では常に null を渡すこと -- 2 枚に絞るだけで
  /// 演算子を明かさないのが、そのレベルを別物として意味あるものにしている。
  /// 呼び出し側は GameSession.hintFormula?.op を渡す想定: エスカレーション
  /// 前は hintFormula 自体が null になるので、自然に null が伝わる。
  final Op? hintedOp;

  final void Function(Op op) onTap;

  /// 電話での、ボタン 1 個あたりの一辺・左右パディング・記号の文字サイズ。
  /// タブレットでは [uiScale] を掛けて拡大する。
  static const double _baseButtonSize = 64;
  static const double _baseHorizontalPadding = 6;
  static const double _baseFontSize = 28;

  const OperatorBar({
    super.key,
    required this.selected,
    this.hintedOp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = uiScale(context);
    final buttonSize = _baseButtonSize * scale;
    // 4 個 x (64px + 左右 6px パディング) = 304px。iPhone SE 級の 320 幅では
    // 本体の Padding(16) を引くと 288px しか残らず、素の Row では右に
    // 16px はみ出す。FittedBox で「収まらない時だけ」縮小し、収まる幅
    // (例: 375px) ではそのままのサイズで描画する。タブレットでボタン自体が
    // 大きくなっても、この仕組みは変えず（万一の保険として）そのまま使う。
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final op in Op.values)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _baseHorizontalPadding * scale,
              ),
              child: SizedBox(
                width: buttonSize,
                height: buttonSize,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: _isMarked(op)
                        ? scheme.primary
                        : scheme.secondaryContainer,
                    foregroundColor: _isMarked(op)
                        ? scheme.onPrimary
                        : scheme.onSecondaryContainer,
                  ),
                  onPressed: () => onTap(op),
                  child: Text(
                    opSymbol(op),
                    style: TextStyle(fontSize: _baseFontSize * scale),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [op] に「選択中の演算子」と同じ見た目（塗り = primary）を与えるか。
  ///
  /// 保留中の選択 (selected) はプレイヤーが直後にカードをタップすれば
  /// 実際に実行される、能動的な意思表示なので常に優先する。ヒントによる
  /// 印は、保留中の選択が無いとき (selected == null) に限って代わりに
  /// 使う。両方を独立に印付けすると、演算子が食い違う場面
  /// (ヒントは保留中とは別の組み合わせを示すことがある) で 2 個の
  /// ボタンが同時に「選択中」に見えてしまい、どちらが実際にタップへ
  /// 効くのか分からなくなるため。
  bool _isMarked(Op op) => op == selected || (selected == null && op == hintedOp);
}
