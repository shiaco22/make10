import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/entitlement_repository.dart';
import '../data/models/entitlement.dart';
import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';
import '../domain/difficulty.dart';
import '../game/game_session.dart';
import '../game/providers.dart';
import '../game/time_attack_session.dart';
import 'difficulty_screen.dart';
import 'game_screen.dart';
import 'remove_ads_screen.dart';
import 'stats_screen.dart';
import 'time_attack_screen.dart';
import 'widgets/responsive.dart';

/// 電話での主要ボタンの大きさ。タブレットでは [uiScale] を掛けて拡大する。
const double _kButtonWidth = 240;
const double _kButtonHeight = 56;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<Difficulty?> _pickDifficulty(
    BuildContext context,
    String title,
  ) {
    return Navigator.of(context).push<Difficulty>(
      MaterialPageRoute(
        builder: (context) => DifficultyScreen(
          title: title,
          onSelected: (d) => Navigator.of(context).pop(d),
        ),
      ),
    );
  }

  /// インタースティシャル判定に使う調整役を先に解決してから画面を積む。
  ///
  /// 呼び出しごとに Riverpod のプロバイダを解決し直すのではなく、ここで
  /// 一度だけ解決してクロージャに閉じ込めておくことで、「次の問題へ」を
  /// 押すたびに走る非同期の連鎖を1段（コーディネータのメソッド呼び出し
  /// だけ）に減らせる -- プレイヤーが3問クリアする頃には確実に解決済みに
  /// なっている。
  Future<void> _startPractice(
    BuildContext context,
    WidgetRef ref,
    PuzzleRepository puzzles,
    StatsRepository stats,
    Difficulty difficulty,
  ) async {
    final coordinator =
        await ref.read(interstitialAdCoordinatorProvider.future);
    if (!context.mounted) return;
    final session = GameSession(
      puzzles: puzzles,
      stats: stats,
      difficulty: difficulty,
    )..start();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GameScreen(
          session: session,
          statusRow: _PuzzleCounterRow(session: session),
          onExit: () => Navigator.of(context).pop(),
          onAdvanceFromCleared: () async {
            await coordinator.onPracticeClearAdvance();
            session.nextPuzzle();
          },
        ),
      ),
    );
  }

  /// 同じ難易度で 1 回分を開始する。
  ///
  /// 「もう一度」は今の画面を閉じてから同じ難易度で開き直す。
  /// TimeAttackSession は使い捨てなので、作り直すのが最も素直。
  Future<void> _startTimeAttack(
    BuildContext context,
    WidgetRef ref,
    PuzzleRepository puzzles,
    StatsRepository stats,
    Difficulty difficulty,
  ) async {
    final coordinator =
        await ref.read(interstitialAdCoordinatorProvider.future);
    if (!context.mounted) return;
    final session = TimeAttackSession(
      puzzles: puzzles,
      stats: stats,
      difficulty: difficulty,
    )..start();
    final navigator = Navigator.of(context);
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (routeContext) => TimeAttackScreen(
              session: session,
              onExit: () => Navigator.of(routeContext).pop(),
              onRetry: () {
                Navigator.of(routeContext).pop();
                unawaited(
                  _startTimeAttack(context, ref, puzzles, stats, difficulty),
                );
              },
              onLeavingResult: coordinator.onLeavingTimeAttackResult,
            ),
          ),
        )
        .then((_) => session.dispose());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzlesAsync = ref.watch(puzzleRepositoryProvider);
    final statsAsync = ref.watch(statsRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: puzzlesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('問題データを読み込めませんでした\n$e',
                  textAlign: TextAlign.center),
            ),
          ),
          data: (puzzles) => statsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (stats) {
              // タブレットでは主要ボタンを拡大する。電話 (scale == 1.0)
              // では幅・高さともに今日と同じ 240x56 / style は null のまま
              // (FilledButton の見た目を一切変えない)。
              final scale = uiScale(context);
              final buttonStyle = scale > 1.0
                  ? FilledButton.styleFrom(
                      textStyle: TextStyle(fontSize: 18 * scale),
                    )
                  : null;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('MAKE 10',
                        style: Theme.of(context).textTheme.displayMedium),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: _kButtonWidth * scale,
                      height: _kButtonHeight * scale,
                      child: FilledButton(
                        style: buttonStyle,
                        onPressed: () async {
                          final d =
                              await _pickDifficulty(context, 'プラクティス');
                          if (d != null && context.mounted) {
                            await _startPractice(
                                context, ref, puzzles, stats, d);
                          }
                        },
                        child: const Text('プラクティス'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: _kButtonWidth * scale,
                      height: _kButtonHeight * scale,
                      child: FilledButton(
                        style: buttonStyle,
                        onPressed: () async {
                          final d =
                              await _pickDifficulty(context, 'タイムアタック');
                          if (d != null && context.mounted) {
                            await _startTimeAttack(
                                context, ref, puzzles, stats, d);
                          }
                        },
                        child: const Text('タイムアタック'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => StatsScreen(stats: stats),
                        ),
                      ),
                      child: const Text('統計'),
                    ),
                    // Web では google_mobile_ads/in_app_purchase のどちらも
                    // 常に「何もしない」実装 (WebAdGateway/WebBillingGateway)
                    // になり、広告は最初から一切出ない。出ない広告を消す
                    // 購入を持ちかけても機能しない導線でしかないので、
                    // Web ビルドではこの入口自体を出さない。
                    if (!kIsWeb) _RemoveAdsEntry(scale: scale),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// プラクティスの [GameScreen.statusRow] に差し込む問題番号表示（仕様
/// §9.1）。タイムアタックは自前の statusRow（残り時間とスコア）を組むので
/// このウィジェットとは無関係 — GameSession.puzzleNumber 自体は両モードに
/// 存在するが、表示するかどうかは呼び出し側のこの一箇所だけで決まる。
///
/// [GameScreen] は自身も [session] の変化のたびに再構築されるが、その
/// 「次に何を描くか」は MaterialPageRoute.builder が最初に一度だけ渡した
/// [GameScreen.statusRow] の値そのものに委ねられている。つまり素の
/// Text では最初の問題番号のまま更新されない。session を直接購読する
/// AnimatedBuilder にすることで、このウィジェット自身が独立して
/// 再描画され、問題が進むたびに数字を更新できる。
class _PuzzleCounterRow extends StatelessWidget {
  final GameSession session;

  const _PuzzleCounterRow({required this.session});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => Text(
        '問題 ${session.puzzleNumber}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// ホーム画面の「広告を消す」導線。
///
/// [EntitlementRepository] は [ChangeNotifier] なので、[RemoveAdsScreen] で
/// 購入や restore が成立した瞬間 -- ホームへ戻る前でも -- このラベルが
/// 追従する。読み込み中・エラー時はまだ権利の有無が分からないので、
/// 「未購入」側の表示にフォールバックする（安全側 = 広告が出ている前提の
/// 表示に倒す）。
class _RemoveAdsEntry extends ConsumerWidget {
  final double scale;

  const _RemoveAdsEntry({required this.scale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlementAsync = ref.watch(entitlementRepositoryProvider);
    return entitlementAsync.when(
      loading: () => const SizedBox(height: 8),
      error: (_, _) => _entry(context, ref, null),
      data: (entitlements) => AnimatedBuilder(
        animation: entitlements,
        builder: (context, _) => _entry(context, ref, entitlements),
      ),
    );
  }

  Widget _entry(
    BuildContext context,
    WidgetRef ref,
    EntitlementRepository? entitlements,
  ) {
    final entitled = entitlements?.isEntitled() ?? false;
    final label = entitled
        ? '広告オフ中(${entitlements!.state.source.label})'
        : '広告を消す';
    return TextButton(
      style: scale > 1.0
          ? TextButton.styleFrom(textStyle: TextStyle(fontSize: 14 * scale))
          : null,
      onPressed: entitlements == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RemoveAdsScreen(
                    billing: ref.read(billingGatewayProvider),
                    entitlements: entitlements,
                  ),
                ),
              ),
      child: Text(label),
    );
  }
}
