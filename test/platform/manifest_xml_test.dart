import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `AndroidManifest.xml` と `Info.plist` は Dart のテストからは普段触らないが、
/// 壊れても `flutter test` は緑のままで、Gradle が
/// `ManifestMerger2$MergeFailureException: Error parsing AndroidManifest.xml`
/// を出すまで誰も気づかない。実際に一度そうなった。
///
/// 原因は XML コメント内の `--`。仕様上コメント本文に `--` は書けないが、
/// 注釈の区切りとしてつい書いてしまう。AdMob のアプリ ID を追記した際の
/// 長いコメントで踏んだ。
///
/// これらのファイルは Android/iOS のビルドでしか読まれないため、この
/// プロジェクトの主要な検証経路（`flutter test` と `flutter build web`）を
/// すべてすり抜ける。ビルドできない環境でも壊れたことが分かるように、
/// ここで最低限の構文だけ見張る。
void main() {
  const files = [
    'android/app/src/main/AndroidManifest.xml',
    'ios/Runner/Info.plist',
  ];

  for (final path in files) {
    group(path, () {
      late String source;

      setUpAll(() {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path が見つからない');
        source = file.readAsStringSync();
      });

      test('コメント本文に `--` を含まない', () {
        // XML の仕様（W3C XML 1.0 §2.5）でコメント本文に `--` は書けない。
        final comments = RegExp(r'<!--(.*?)-->', dotAll: true)
            .allMatches(source)
            .map((m) => m.group(1)!);
        for (final body in comments) {
          expect(
            body.contains('--'),
            isFalse,
            reason: 'XML コメントに `--` が含まれている。'
                'パーサが弾くので Android/iOS のビルドが失敗する:\n'
                '${body.trim()}',
          );
        }
      });

      test('コメントが閉じている', () {
        final opens = '<!--'.allMatches(source).length;
        final closes = '-->'.allMatches(source).length;
        expect(opens, closes, reason: 'コメントの開きと閉じの数が合わない');
      });
    });
  }

  test('AndroidManifest が AdMob のアプリ ID を宣言している', () {
    // 値が無い・壊れていると AdMob SDK はプロセス起動時にクラッシュする。
    // 単に存在するだけでなく、`ca-app-pub-…~…` の形であることまで見る。
    final source =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(source, contains('com.google.android.gms.ads.APPLICATION_ID'));
    expect(
      RegExp(r'android:value="ca-app-pub-\d+~\d+"').hasMatch(source),
      isTrue,
      reason: 'AdMob のアプリ ID が ca-app-pub-<数字>~<数字> の形になっていない',
    );
  });

  test('Info.plist が AdMob のアプリ ID を宣言している', () {
    final source = File('ios/Runner/Info.plist').readAsStringSync();
    expect(source, contains('GADApplicationIdentifier'));
    expect(
      RegExp(r'<string>ca-app-pub-\d+~\d+</string>').hasMatch(source),
      isTrue,
      reason: 'GADApplicationIdentifier の値が ca-app-pub-<数字>~<数字> の形になっていない',
    );
  });
}
