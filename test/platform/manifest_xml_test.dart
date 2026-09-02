import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:make10/monetization/ads/ad_unit_ids.dart';

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
///
/// さらに、`AndroidManifest.xml`/`Info.plist` の AdMob アプリ ID は
/// `lib/monetization/ads/ad_unit_ids.dart` の [AdUnitIds] と手で同期する
/// 値（マニフェスト/plist は静的ファイルなので Dart 側から実行時に読ませる
/// ことができない）。この二重管理そのものは無くせないので、値が
/// `ca-app-pub-<数字>~<数字>` の形であることだけでなく、[AdUnitIds] が
/// 報告する値と一字一句一致することまでここで検査し、ズレを機械的に
/// 検知できるようにする。
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

  test('AndroidManifest の AdMob アプリ ID が Android 本番の ID と一字一句一致する', () {
    // 形（ca-app-pub-<数字>~<数字>）だけでなく、AdUnitIds.androidAppId
    // （Android 本番のアプリ ID、プロダクトオーナーに確認済み）と完全に
    // 一致することを見る。ここが唯一、マニフェストと Dart 側の定義元が
    // ズレていないことを保証できる場所。
    final source =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(source, contains('com.google.android.gms.ads.APPLICATION_ID'));
    expect(
      RegExp(r'android:value="ca-app-pub-\d+~\d+"').hasMatch(source),
      isTrue,
      reason: 'AdMob のアプリ ID が ca-app-pub-<数字>~<数字> の形になっていない',
    );
    expect(
      source,
      contains('android:value="${AdUnitIds.androidAppId}"'),
      reason: 'AndroidManifest.xml の com.google.android.gms.ads.APPLICATION_ID '
          'が AdUnitIds.androidAppId (${AdUnitIds.androidAppId}) と一致しない。'
          'lib/monetization/ads/ad_unit_ids.dart を変更したら、このファイルも'
          '手で同期すること',
    );
  });

  test('Info.plist の AdMob アプリ ID はまだ Google 公式のテスト ID のまま', () {
    // iOS 用の AdMob アプリはまだ登録されていない（AdUnitIds のクラス doc
    // コメント参照）ので、本番 ID に差し替えてはいけない。Android 本番の
    // ID を誤って使い回していないことも、この一致比較が防ぐ。
    final source = File('ios/Runner/Info.plist').readAsStringSync();
    expect(source, contains('GADApplicationIdentifier'));
    expect(
      RegExp(r'<string>ca-app-pub-\d+~\d+</string>').hasMatch(source),
      isTrue,
      reason: 'GADApplicationIdentifier の値が ca-app-pub-<数字>~<数字> の形になっていない',
    );
    expect(
      source,
      contains('<string>${AdUnitIds.testAppId}</string>'),
      reason: 'Info.plist の GADApplicationIdentifier が Google 公式のテスト ID '
          '(${AdUnitIds.testAppId}) のままになっていない。iOS 用の AdMob '
          'アプリはまだ登録されていないので、本番 ID（まして Android のもの）'
          'に差し替えてはいけない',
    );
    expect(
      source,
      isNot(contains(AdUnitIds.androidAppId)),
      reason: 'Info.plist に Android 本番の AdMob アプリ ID が混入している。'
          'iOS 用の AdMob アプリはまだ存在しないので、Android の本番 ID を '
          'iOS で使い回すのは誤設定になる',
    );
  });
}
