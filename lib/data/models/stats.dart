/// プラクティスの難易度別集計。
class PracticeStats {
  final int solved;
  final int totalTimeMs;
  final int hintUsed;
  final int answerShown;
  final int skipped;

  const PracticeStats({
    this.solved = 0,
    this.totalTimeMs = 0,
    this.hintUsed = 0,
    this.answerShown = 0,
    this.skipped = 0,
  });

  /// 平均解答時間。まだ 1 問もクリアしていなければ null。
  int? get averageTimeMs => solved == 0 ? null : totalTimeMs ~/ solved;

  PracticeStats copyWith({
    int? solved,
    int? totalTimeMs,
    int? hintUsed,
    int? answerShown,
    int? skipped,
  }) =>
      PracticeStats(
        solved: solved ?? this.solved,
        totalTimeMs: totalTimeMs ?? this.totalTimeMs,
        hintUsed: hintUsed ?? this.hintUsed,
        answerShown: answerShown ?? this.answerShown,
        skipped: skipped ?? this.skipped,
      );

  Map<String, dynamic> toJson() => {
        'solved': solved,
        'totalTimeMs': totalTimeMs,
        'hintUsed': hintUsed,
        'answerShown': answerShown,
        'skipped': skipped,
      };

  factory PracticeStats.fromJson(Map<String, dynamic> json) => PracticeStats(
        solved: json['solved'] as int? ?? 0,
        totalTimeMs: json['totalTimeMs'] as int? ?? 0,
        hintUsed: json['hintUsed'] as int? ?? 0,
        answerShown: json['answerShown'] as int? ?? 0,
        skipped: json['skipped'] as int? ?? 0,
      );
}

/// タイムアタックの難易度別集計。
class TimeAttackStats {
  final int bestScore;
  final int playCount;

  const TimeAttackStats({this.bestScore = 0, this.playCount = 0});

  Map<String, dynamic> toJson() =>
      {'bestScore': bestScore, 'playCount': playCount};

  factory TimeAttackStats.fromJson(Map<String, dynamic> json) =>
      TimeAttackStats(
        bestScore: json['bestScore'] as int? ?? 0,
        playCount: json['playCount'] as int? ?? 0,
      );
}
