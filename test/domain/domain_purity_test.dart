import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/domain/` は Flutter に依存しない、という規約を機械的に見張る。
///
/// これまでこの規約は `tool/generate_puzzles.dart` が `dart run` で
/// コンパイルされることで間接的に守られていた（`package:flutter` を
/// import したファイルは素の `dart run` で落ちる）。ただしその経路が
/// カバーするのは、あのスクリプトが実際に import しているファイルだけ
/// である。ドメイン層に新しいファイルが増えるとカバー範囲から静かに
/// 外れるので、ここでディレクトリ全体を見る。
void main() {
  test('lib/domain/ は package:flutter を import しない', () {
    final dir = Directory('lib/domain');
    expect(dir.existsSync(), isTrue, reason: 'lib/domain/ が見つからない');

    final offenders = <String>[];
    final checked = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      checked.add(path);
      final source = entity.readAsStringSync();
      for (final line in source.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('package:flutter/') ||
            trimmed.contains('package:flutter_test/')) {
          offenders.add('$path: $trimmed');
        }
      }
    }

    expect(checked, isNotEmpty, reason: '.dart ファイルが 1 つも見つからない');
    expect(
      offenders,
      isEmpty,
      reason: 'lib/domain/ 配下が Flutter に依存している。ドメイン層は '
          '`dart run` だけで動く純粋な Dart に保つ:\n${offenders.join('\n')}',
    );
  });
}
