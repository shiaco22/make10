import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bonus_repository.dart';
import '../data/entitlement_repository.dart';
import '../data/models/entitlement.dart';
import '../data/puzzle_repository.dart';
import '../data/stats_repository.dart';
import '../domain/bonus/bonus_grid.dart';
import '../domain/bonus_ticket.dart';
import '../domain/difficulty.dart';
import '../game/bonus_session.dart';
import '../game/game_session.dart';
import '../game/providers.dart';
import '../game/time_attack_session.dart';
import 'bonus_game_screen.dart';
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
    final bonus = await ref.read(bonusRepositoryProvider.future);
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
              onFinished: (score) async {
                if (score < kBonusUnlockClears) return;
                await bonus.earn(bonusDateKey(DateTime.now()));
              },
              resultNotice: _BonusUnlockNotice(bonus: bonus),
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
                    _StatsEntry(stats: stats),
                    _BonusEntry(scale: scale),
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

/// ホーム画面のボーナスゲームの入口。
///
/// 4 状態を出し分ける。**未解禁でも隠さず条件を出す** — メカニクスを
/// 知らせる導線になり、タイムアタックを遊ぶ理由にもなる（仕様 §7.1）。
///
/// [BonusRepository] は [ChangeNotifier] なので、タイムアタックのリザルトで
/// 解禁した瞬間に（ホームへ戻る前でも）このラベルが追従する。読み込み中・
/// エラー時はまだ状態が分からないので、押せない側にフォールバックする
/// （既存 [_RemoveAdsEntry] と同じ扱い）。
///
/// [ConsumerWidget] ではなく [ConsumerStatefulWidget] にしているのは
/// [_starting] を保持するため。連打対策の詳細は [_start] のコメント参照。
class _BonusEntry extends ConsumerStatefulWidget {
  final double scale;

  const _BonusEntry({required this.scale});

  @override
  ConsumerState<_BonusEntry> createState() => _BonusEntryState();
}

class _BonusEntryState extends ConsumerState<_BonusEntry> {
  /// [_start] が既に実行中かの印。
  ///
  /// 新規ゲームの分岐は `await bonus.startGame(...)` を挟む。
  /// `BonusRepository.startGame` は権利の消費と `inProgressGrid` の設定を
  /// その await の**前**（同期区間）で済ませてしまうため、ガードが無いと
  /// 連打した 2 回目のタップは「中断あり」に見えて `resumed != null` の
  /// 分岐に入ってしまう — 権利が二重消費されるわけではないが、1 回目とは
  /// 別の [BonusSession] を新たに作って [BonusGameScreen] をもう一つ
  /// Navigator に積んでしまう（同じ盤面を指す独立したセッションが 2 つ
  /// 並存し、どちらを操作するかで保存されるスコアが食い違う）。
  /// [_starting] はこの再入を防ぎ、1 回のタップ操作につき 1 回だけ
  /// 実行させる。
  bool _starting = false;

  Future<void> _start(
    BuildContext context,
    BonusRepository bonus,
  ) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final today = bonusDateKey(DateTime.now());
      // 中断した盤面があればそれを再開する。無ければ新しく配って権利を
      // 消費する。権利の消費を開始時に置くのは、完了時だと強制終了で
      // 無限にリトライできてしまうため（仕様 §4.3）。
      final resumed = bonus.inProgressGrid;
      final BonusGrid grid;
      final int score;
      if (resumed != null) {
        grid = resumed;
        score = bonus.inProgressScore;
      } else {
        grid = BonusGrid.deal(Random());
        score = 0;
        await bonus.startGame(today, grid);
      }
      // ここで消費・保存は既に確定している（startGame は await の前で
      // 同期的に済ませ、保存まで終えてから戻る）。以降 context が
      // unmounted で戻っても、権利だけ失われて何も始まらない、という
      // ことにはならない — 中断あり状態としてホームに残り、次に
      // 「続きから」で拾える。
      if (!context.mounted) return;

      // bonus.inProgressRepairsUsed はここで読む(startGame の後)。
      // startGame は同期区間で _inProgressRepairsUsed を 0 にしてから
      // 保存まで終えているので、新規開始なら 0、再開なら永続化されていた
      // 値がそのまま読める。順序を逆にすると新規開始でも前回のゲームの
      // 値が残ってしまう(仕様 §3.4)。
      final session = BonusSession(
        repository: bonus,
        grid: grid,
        score: score,
        repairsUsed: bonus.inProgressRepairsUsed,
      );
      final navigator = Navigator.of(context);
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (routeContext) => BonusGameScreen(
            session: session,
            onExit: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
      session.dispose();
    } finally {
      // ゲーム画面を積んでいる間はホーム画面のこのボタン自体が見えない
      // ので実害は無いが、ポップされてホームに戻ったら次のタップを
      // 受け付けられるようにする。早期 return した経路でも必ずここを
      // 通るので、_starting が true のまま固まることはない。
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bonusAsync = ref.watch(bonusRepositoryProvider);
    return bonusAsync.when(
      loading: () => const SizedBox(height: 8),
      error: (_, _) => const SizedBox(height: 8),
      data: (bonus) => AnimatedBuilder(
        animation: bonus,
        builder: (context, _) => _entry(context, bonus),
      ),
    );
  }

  Widget _entry(BuildContext context, BonusRepository bonus) {
    final today = bonusDateKey(DateTime.now());
    final String label;
    final bool enabled;
    if (bonus.hasInProgress) {
      // 中断が最優先。権利は消費済みでも続きは遊べる。
      label = 'ボーナスゲーム（続きから）';
      enabled = true;
    } else if (bonus.ticket.isAvailable(today)) {
      label = '★ ボーナスゲーム';
      enabled = true;
    } else if (bonus.ticket.playedOn == today) {
      label = 'ボーナスゲーム（また明日） ベスト ${bonus.bestScore}';
      enabled = false;
    } else {
      label = 'ボーナスゲーム（タイムアタックで$kBonusUnlockClears問クリア）';
      enabled = false;
    }

    return TextButton(
      style: widget.scale > 1.0
          ? TextButton.styleFrom(
              textStyle: TextStyle(fontSize: 14 * widget.scale))
          : null,
      onPressed:
          enabled && !_starting ? () => _start(context, bonus) : null,
      child: Text(label),
    );
  }
}

/// タイムアタックのリザルトに出す、ボーナスゲーム解禁の告知。
///
/// [BonusRepository] を購読しているので、`onFinished` が非同期に
/// `earn` を終えた時点で自動的に現れる。5 問未満だった勝負では
/// `earn` が呼ばれないので、何も描かない。
class _BonusUnlockNotice extends StatelessWidget {
  final BonusRepository bonus;

  const _BonusUnlockNotice({required this.bonus});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bonus,
      builder: (context, _) {
        final today = bonusDateKey(DateTime.now());
        if (!bonus.ticket.isAvailable(today)) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ボーナスゲーム解禁!',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text('ホームから遊べます', style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

/// ホーム画面の統計への入口。
///
/// [StatsScreen] にボーナスのベストスコアも渡したいが、
/// [bonusRepositoryProvider] は非同期なので、ここで解決してから積む。
/// 読み込みが終わっていなければボーナスの欄を省いて開く（統計そのものは
/// 見られるべきなので、ボーナスの都合で入口を塞がない）。
class _StatsEntry extends ConsumerWidget {
  final StatsRepository stats;

  const _StatsEntry({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bonus = ref.watch(bonusRepositoryProvider).value;
    return TextButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StatsScreen(stats: stats, bonus: bonus),
        ),
      ),
      child: const Text('統計'),
    );
  }
}
