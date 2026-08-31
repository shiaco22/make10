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

/// [_kMaxScale] に到達する画面の短辺サイズ。iPad Pro 12.9 インチの短辺
/// (1024pt) に合わせてある。これより大きな画面が来ても、際限なく拡大は
/// 続けない。
const double _kMaxScaleShortestSide = 1024;

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
