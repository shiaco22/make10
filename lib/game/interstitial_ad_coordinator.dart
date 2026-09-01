import '../data/entitlement_repository.dart';
import '../domain/ad_policy.dart';
import '../monetization/ads/ad_gateway.dart';

/// 「広告を出してよいかの判断」（[AdPolicy]、`lib/domain/`）・「実際に広告を
/// 出す窓口」（[AdGateway]、`lib/monetization/ads/`）・「エンタイトルメント」
/// （[EntitlementRepository]、`lib/data/`）の3つを実際のゲーム進行のイベント
/// に結び付ける、薄い調整役。
///
/// UI 層（`GameScreen`/`HomeScreen`/`TimeAttackScreen`）はこれらを個別に
/// 触らず、常にこのクラス経由で扱う。アプリ全体でインスタンスを1つだけ
/// 共有する想定（`lib/game/providers.dart` の
/// `interstitialAdCoordinatorProvider` 参照）-- [AdPolicy] のカウンタは
/// プラクティスの3問区切りをまたいで（さらにはタイムアタックへの行き来を
/// またいでも）生き続ける必要があるため、呼び出しのたびに作り直しては
/// いけない。
class InterstitialAdCoordinator {
  final AdPolicy policy;
  final AdGateway gateway;
  final EntitlementRepository entitlements;

  /// 変化した [AdPolicy.clearsSinceLastAd] を永続化する。呼び出しのたびに
  /// 保存先へ書き込む（通常は `AdPolicyRepository.save` を渡す）。
  final Future<void> Function(int clearsSinceLastAd) persistClearsSinceLastAd;

  InterstitialAdCoordinator({
    required this.policy,
    required this.gateway,
    required this.entitlements,
    required this.persistClearsSinceLastAd,
  });

  /// プラクティスで、クリア直後の「次の問題へ」がタップされた時に呼ぶ。
  ///
  /// クリアそのものはこの呼び出しの直前に確定している前提 -- 呼び出し側は
  /// `GameSession.phase == PhaseKind.cleared` の状態からこのタップが起きた
  /// 時だけこれを呼ぶこと（answerShown からの「次の問題へ」では呼ばない。
  /// 答えを見た問題はそもそも「クリア」ではない）。「クリア!」の表示中では
  /// なく、そこから離れる操作の瞬間に判定することで、成功の瞬間に広告が
  /// 割り込む最悪の体験を避ける。
  Future<void> onPracticeClearAdvance() async {
    policy.recordClear(GameMode.practice);
    await _maybeShow(GameMode.practice, AdCheckpoint.puzzleCleared);
    await persistClearsSinceLastAd(policy.clearsSinceLastAd);
  }

  /// タイムアタックのリザルト画面を離れる操作（「もう一度」または
  /// 「ホームへ」）の直前に呼ぶ。
  ///
  /// スコアは既にリザルト画面に表示された後、というタイミングは呼び出し側
  /// （TimeAttackScreen）が保証する -- リザルト到達そのものではなく、
  /// そこから離れる操作にひも付けることで、ご褒美であるスコア表示を広告が
  /// 隠さないようにする。
  Future<void> onLeavingTimeAttackResult() async {
    await _maybeShow(GameMode.timeAttack, AdCheckpoint.resultScreen);
  }

  Future<void> _maybeShow(GameMode mode, AdCheckpoint checkpoint) async {
    final due = policy.shouldShowInterstitial(
      mode: mode,
      checkpoint: checkpoint,
      isEntitled: entitlements.isEntitled(),
    );
    if (!due) return;
    // 読み込みが間に合っていなければ、ここで待たずに諦める --
    // ゲームプレイは絶対に広告の読み込みを待ってはいけない。カウンタは
    // 消費しない（onInterstitialShown を呼ばない）ので、次に読み込みが
    // 間に合ったときに改めて表示対象になる。
    if (!gateway.isAdReady) return;
    await gateway.showIfAvailable();
    policy.onInterstitialShown();
  }
}
