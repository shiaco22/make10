import 'package:flutter/widgets.dart';

/// 画面の「短辺」がこの論理ピクセル数以上になったら、タブレット向けの
/// 拡大レイアウト ([uiScale] が 1.0 より大きい値を返す領域) に入る。
///
/// 600 は Material Design がタブレット判定に使う慣例的なブレークポイント
/// であり、最大級の iPhone (横幅 430pt 前後) と最小の iPad
/// (短辺 744pt, iPad mini) の間に十分な余裕を持って収まる。
const double kTabletBreakpoint = 600;

/// タブレットで到達する最大の拡大率。
const double _kMaxScale = 1.6;

/// [_kMaxScale] に到達する画面の短辺サイズ。
///
/// iPad / iPad Air の短辺 (820pt) に合わせてある。以前は iPad Pro 12.9
/// インチの短辺 (1024pt) に合わせていたが、その設定だと最も一般的な
/// iPad/Air (820pt) がカーブの 8 割強 (~1.31 倍) にしか届かず、ボタンも
/// 盤面もタブレットとしては控えめすぎた。820pt で最大値に届くようにする
/// ことで、一般的な iPad は「タブレット向けに拡大した」と実感できる
/// 大きさになる。iPad Pro 12.9 インチ (1024pt) は 820pt を超えるので
/// 同じ [_kMaxScale] で頭打ちになるだけ -- 以前と全く同じ拡大率のままで、
/// より大きな画面でも UI が過剰に肥大化しない。
///
/// これより小さいタブレット (iPad mini, 短辺 744pt) は 820pt に届かない
/// ぶんカーブの途中 (~1.39 倍) に位置する。iPad mini は横向きにしても
/// 短辺 (=高さ) が 744pt のまま変わらないため、盤面・演算子バー・
/// アクションバーが縦に収まりきるかを最も厳しく試す画面でもある
/// (test/ui/tablet_layout_test.dart の iPad mini 横向きのテストで検証)。
const double _kMaxScaleShortestSide = 820;

/// 現在のビューポートに応じた UI 拡大率。
///
/// 電話サイズ (画面の短辺が [kTabletBreakpoint] 未満) では常に `1.0` を
/// 返し、今日の見た目を一切変えない。タブレットサイズでは短辺の大きさに
/// 応じて `1.0` から [_kMaxScale] まで滑らかに増える。
///
/// 「幅」ではなく「短辺 (shortestSide)」を見ているのが要点:
///
/// * 同じ端末なら縦向き・横向きを問わず同じ拡大率になる
///   (例: iPad mini は 744x1133 でも 1133x744 でも短辺は 744)。
///   向きが変わって余白の使い方が変わっても、余白の「量」自体は端末固有の
///   ものとして扱える。
/// * 横向き iPad の中でもっとも縦方向の余裕が乏しい端末 (iPad mini の
///   横向き, 高さ 744) は、短辺もタブレットの中で最小なので、自動的に
///   拡大率も一番控えめになる。盤面の下に並ぶ演算子バー・アクションバーを
///   押し出してしまうリスクが、縦の余裕が少ない画面ほど小さい拡大率で
///   済むことで自然に和らぐ。
double uiScale(BuildContext context) {
  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
  if (shortestSide < kTabletBreakpoint) return 1.0;
  final t = ((shortestSide - kTabletBreakpoint) /
          (_kMaxScaleShortestSide - kTabletBreakpoint))
      .clamp(0.0, 1.0);
  return 1.0 + t * (_kMaxScale - 1.0);
}
