import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/board.dart';

/// 盤面の 1 枚。選択中とヒント強調で見た目を変える。
///
/// サイズは呼び出し側（[BoardView]）が利用可能な余白から計算して渡す。
/// [baseWidth] × [baseHeight] (88×112) が既定値であり、同時に
/// BoardView 側での上限（タブレットで拡大しすぎない）としても使われる。
///
/// [shakeSignal] が変化するたびに横揺れアニメーションを再生する
/// （拒否された合成の対象カードであることを表す。仕様 §2.5 / §10）。
/// このウィジェット自身はゲームロジックを持たない — 「いつ震えるか」は
/// 呼び出し側が [shakeSignal] の値で伝える。値そのものに意味はなく、
/// 前回のビルドと異なることだけを見るので、同じカードへの同じ理由の
/// 拒否が連続しても（呼び出し側が渡す値さえ変わっていれば）毎回震える。
class CardTile extends StatefulWidget {
  final CardItem card;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final double width;
  final double height;
  final Object? shakeSignal;

  /// カードの既定サイズ。88:112 の縦横比を保つ。
  static const double baseWidth = 88;
  static const double baseHeight = 112;

  const CardTile({
    super.key,
    required this.card,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    this.width = baseWidth,
    this.height = baseHeight,
    this.shakeSignal,
  });

  @override
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile>
    with SingleTickerProviderStateMixin {
  static const Duration _shakeDuration = Duration(milliseconds: 400);

  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: _shakeDuration,
    );
  }

  @override
  void didUpdateWidget(covariant CardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // shakeSignal が非 null かつ前回から変化した時だけ再生する。null への
    // 変化（拒否が他の経路で消えた場合）では再生しない — 消える動きを
    // 震えと誤解させないため。
    if (widget.shakeSignal != null &&
        widget.shakeSignal != oldWidget.shakeSignal) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color background;
    final Color foreground;
    if (widget.selected) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (widget.highlighted) {
      background = scheme.tertiaryContainer;
      foreground = scheme.onTertiaryContainer;
    } else {
      // 通常状態: 以前はここを scheme.outline のベタ塗りにしていた
      // (theme.cardColor が M3 既定で colorScheme.surface になり、
      // Scaffold の背景と同色でカード自体が見えなくなっていたのが直前の
      // 不具合。outline はページに対して両テーマとも 3:1 を大きく超える
      // コントラストを安定して持つため、それを塗りに使えば数字とカードの
      // 両方が見えるようにはなった)。
      //
      // ただし outline は彩度の低い middle-grey で、カード全面をそれで
      // 塗ると「死んだプレースホルダーの板」に見え、淡い tertiaryContainer
      // のハイライト状態より視覚的に主張しすぎてしまう。
      //
      // WCAG 2.1 SC 1.4.11 (Non-text Contrast) が実際に求めているのは
      // 「コンポーネントの境界」がページに対して 3:1 であることであって、
      // 塗り自体が 3:1 である必要はない。淡い塗り + はっきりした縁取りは、
      // 物理的なトランプ札の見え方と同じで、それだけで十分「カードだ」と
      // 読める。そこで塗りはページに近い明るい surface 系トークン
      // (surfaceContainerHighest -- Flutter の Card ウィジェットの
      // filled/elevated バリアントが既定で使うのと同じトーン) に戻し、
      // 3:1 の担保は下の borderColor 側の outline に移す
      // (色そのものは変えていないので、以前計測した light 4.27 / dark
      // 5.87 のコントラスト比がそのまま境界線に引き継がれる)。
      // onSurface は M3 の設計上 surface 系トークン全般に対して強い
      // コントラストを持つよう作られているため、数字の可読性は両テーマ
      // とも保たれる。
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurface;
    }

    final Color borderColor;
    if (widget.selected && widget.highlighted) {
      // 塗りは primary (選択中が優先) だが、Material 3 では primary と
      // tertiary はトーンが近くほぼ無彩色差になり得るため、実際に塗られる
      // primary に対して確実にコントラストが取れる onPrimary を使う。
      borderColor = scheme.onPrimary;
    } else if (widget.highlighted) {
      borderColor = scheme.tertiary;
    } else if (widget.selected) {
      // 選択中 (ハイライト無し): 塗りの primary 自体がページに対し
      // はっきりしたコントラストを持つ、彩度の高い色なので、縁取りは
      // 要らない。
      borderColor = Colors.transparent;
    } else {
      // 通常状態: 上のとおり淡い塗りだけではページとの境界が曖昧なので、
      // ここで outline の縁取りを与えて WCAG 1.4.11 の 3:1 を満たす。
      borderColor = scheme.outline;
    }

    return Semantics(
      button: true,
      label: 'カード ${widget.card.value}',
      // 付けないと内側の Text が生成する暗黙のラベルがマージされ、
      // 読み上げが「カード 9\n9」のように重複してしまう。
      excludeSemantics: true,
      // 上記で子孫の Semantics (InkWell 内のタップ操作を含む) を遮断する
      // ため、タップ操作はここで明示的に再提供する。
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          final t = _shakeController.value;
          // 減衰する正弦波で横方向に揺らす。振幅は (1 - t) で 0 まで
          // 減衰するので、開始 (t=0) と終了 (t=1) は必ずオフセット 0 に
          // なり、震え終わりが元の位置にきちんと戻る。
          final dx = math.sin(t * math.pi * 3) * 10 * (1 - t);
          return Transform.translate(
            offset: Offset(dx, 0),
            child: child,
          );
        },
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: 3,
              ),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${widget.card.value}',
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
      ),
    );
  }
}
