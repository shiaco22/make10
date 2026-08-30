enum Difficulty { easy, normal, hard }

extension DifficultyDisplay on Difficulty {
  /// UI 表示名。
  String get label {
    switch (this) {
      case Difficulty.easy:
        return 'やさしい';
      case Difficulty.normal:
        return 'ふつう';
      case Difficulty.hard:
        return 'むずかしい';
    }
  }

  /// JSON と shared_preferences で使うキー。変更すると保存データが読めなくなる。
  String get key {
    switch (this) {
      case Difficulty.easy:
        return 'easy';
      case Difficulty.normal:
        return 'normal';
      case Difficulty.hard:
        return 'hard';
    }
  }
}

Difficulty difficultyFromKey(String key) {
  return Difficulty.values.firstWhere((d) => d.key == key);
}

/// 解の本数を難易度に分ける境界。いずれも「以下」で判定する。
class Thresholds {
  final int hard;
  final int normal;

  const Thresholds({required this.hard, required this.normal});

  Map<String, dynamic> toJson() => {'hard': hard, 'normal': normal};

  factory Thresholds.fromJson(Map<String, dynamic> json) => Thresholds(
        hard: json['hard'] as int,
        normal: json['normal'] as int,
      );
}

Difficulty difficultyFor(int solutionCount, Thresholds t) {
  if (solutionCount <= t.hard) return Difficulty.hard;
  if (solutionCount <= t.normal) return Difficulty.normal;
  return Difficulty.easy;
}

/// 解の本数の 33 / 67 パーセンタイルを境界として返す。
Thresholds computeThresholds(List<int> solutionCounts) {
  final sorted = List.of(solutionCounts)..sort();
  final n = sorted.length;
  return Thresholds(
    hard: sorted[n ~/ 3],
    normal: sorted[2 * n ~/ 3],
  );
}
