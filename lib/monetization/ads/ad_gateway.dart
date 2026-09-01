// プラグイン（google_mobile_ads）は Android/iOS 専用。Web ビルドがこの
// プラグインを一切参照しないよう、実装の選択は conditional import で行う —
// `dart.library.io` が使えるとき（Android/iOS/デスクトップ/`flutter test` の
// VM 実行）は `ad_gateway_io.dart`、使えないとき（Web）は
// `ad_gateway_web.dart` にフォールバックする。
//
// このファイル自身はどちらの実装ファイルが選ばれても import されるため、
// プラグインへの参照を一切含めてはいけない。
import 'ad_gateway_web.dart' if (dart.library.io) 'ad_gateway_io.dart' as platform;

/// プラットフォームの広告 SDK（`google_mobile_ads`）をラップするゲートウェイ。
/// Android/iOS 専用 — Web では [createAdGateway] が常に
/// `WebAdGateway`（何も表示しない実装）を返す。
///
/// **ゲームプレイは広告を待ってはいけない**という契約をこのインターフェース
/// 自身が体現している: [showIfAvailable] は広告が読み込まれていなければ
/// 即座に戻る（読み込みを待たない）。[preload] は結果を待たずに呼び出して
/// よく（fire-and-forget）、読み込み完了は [isAdReady] に反映される。
abstract class AdGateway {
  /// SDK の初期化と、最初の [preload] をまとめて行う。起動時に一度だけ呼ぶ。
  Future<void> init();

  /// 次のインタースティシャルの読み込みをバックグラウンドで開始する。
  /// 既に読み込み済み・読み込み中でも安全に呼べる（二重読み込みはしない）。
  Future<void> preload();

  /// 今すぐ表示できるインタースティシャルが読み込み済みか。
  bool get isAdReady;

  /// 読み込み済みのインタースティシャルがあれば表示し、閉じられた後に
  /// 次の読み込みを自動的に始める。読み込み済みの広告が無ければ、
  /// 何も表示せず即座に戻る — 呼び出し側はこれを待ってゲームプレイを
  /// 止めてはいけない。
  Future<void> showIfAvailable();

  /// 読み込み済みの広告があれば解放する。
  Future<void> dispose();
}

/// Android/iOS では `google_mobile_ads` をラップした実装を、Web では常に
/// 「何も表示しない」実装を返す。
AdGateway createAdGateway() => platform.createAdGateway();
