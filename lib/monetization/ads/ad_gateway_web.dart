import 'ad_gateway.dart';

/// Web 版の広告ゲートウェイ。`google_mobile_ads` は Android/iOS 専用のため、
/// Web ビルドではこのファイルが選ばれる（`ad_gateway.dart` の
/// conditional import を参照）。このファイルはプラグインを一切 import
/// しない — それが Web ビルドの成果物にプラグインが混入しないことの保証になる。
///
/// 常に「広告なし」。[isAdReady] は常に false、[showIfAvailable] は常に
/// 何もせず即座に戻る。
class WebAdGateway implements AdGateway {
  @override
  Future<void> init() async {}

  @override
  Future<void> preload() async {}

  @override
  bool get isAdReady => false;

  @override
  Future<void> showIfAvailable() async {}

  @override
  Future<void> dispose() async {}
}

AdGateway createAdGateway() => WebAdGateway();
