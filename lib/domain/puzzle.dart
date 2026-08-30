import 'difficulty.dart';

/// 出題される 1 問。digits は昇順。
class Puzzle {
  final List<int> digits;
  final int solutionCount;

  /// 除算を使わないと解けないか。v1 では難易度に使わず、記録のみ。
  final bool requiresDivision;
  final Difficulty difficulty;

  const Puzzle({
    required this.digits,
    required this.solutionCount,
    required this.requiresDivision,
    required this.difficulty,
  });

  /// 履歴の照合に使う安定キー。digits は昇順なので一意に定まる。
  String get key => digits.join(',');

  Map<String, dynamic> toJson() => {
        'd': digits,
        'n': solutionCount,
        'div': requiresDivision,
        'lv': difficulty.key,
      };

  factory Puzzle.fromJson(Map<String, dynamic> json) => Puzzle(
        digits: List<int>.from(json['d'] as List),
        solutionCount: json['n'] as int,
        requiresDivision: json['div'] as bool,
        difficulty: difficultyFromKey(json['lv'] as String),
      );
}
