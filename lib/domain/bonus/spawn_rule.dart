import 'dart:math';

/// 上から補充される数字を決める(仕様 §2.4)。
///
/// 範囲は `1 .. max(1, boardMax - 1)`、値 `v` の重みは `1 / √v`。
///
/// **範囲の下端が常に 1 であることが要点。** 盤面がどれだけ育っても 1 は
/// 湧き続ける。サンプルゲームの観測(盤面の最大が 9 の局面でも 1 が
/// 出現していた)に合わせた要件であると同時に、「低い数字が湧かなくなると
/// 取り残された低いマスが二度と合成できず盤面を塞ぐ」という不具合を
/// 構造的に防いでいる。範囲を `[boardMax - 3, boardMax - 1]` にする案は、
/// 最大 9 で 1 の出現率が 0.0% になり観測と矛盾するため棄却した
/// (仕様 §10.1)。
///
/// `1 / √v` という重みは実測で選んだ。1 の出現率 22.9%(体感できる割合)と
/// 10 到達までの所要 5 分前後が両立する点である(仕様 §3.1)。

/// [boardMax] のときに抽選対象になる値ごとの重み。添字 0 が値 1 に対応する。
List<double> spawnWeights(int boardMax) {
  final hi = boardMax - 1 < 1 ? 1 : boardMax - 1;
  return List<double>.generate(hi, (i) => 1 / sqrt(i + 1));
}

/// [boardMax] のときに湧く数字を 1 つ引く。
int spawnValue(int boardMax, Random random) {
  final weights = spawnWeights(boardMax);
  if (weights.length == 1) return 1;
  var total = 0.0;
  for (final w in weights) {
    total += w;
  }
  final target = random.nextDouble() * total;
  var acc = 0.0;
  for (var i = 0; i < weights.length; i++) {
    acc += weights[i];
    if (target < acc) return i + 1;
  }
  // 浮動小数の誤差で acc が total にわずかに届かなかった場合の保険。
  // 分布に意味のある偏りを与えない(最後の 1 つに寄るだけ)。
  return weights.length;
}
