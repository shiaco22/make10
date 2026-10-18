# MAKE10 — 作業メモ

Flutter 製のパズルゲーム。README が何を作っているかを説明する。これは
**踏みやすい地雷と、リポジトリ外の状態**を書いたもの。

## 絶対に忘れてはいけない2つ

### 1. AGP 9 の R8 はコンストラクタを消す

`android/app/proguard-rules.pro` の2行を消さないこと。消すと**リリース
ビルドだけ**が起動直後にクラッシュする。

```
java.lang.RuntimeException: Unable to get provider
  androidx.startup.InitializationProvider
Caused by: Failed to create an instance of androidx.work.impl.WorkDatabase
```

AGP 9 の R8 は full mode で動き、クラスを keep してもその引数なし
コンストラクタは残らない。Room の同梱ルールはメンバーを指定していないため、
`WorkDatabase_Impl.<init>()` が削除される。WorkManager は `androidx.startup`
の ContentProvider からそれを呼ぶ。つまり `Application.onCreate` より前、
Flutter が動き出すより前に落ちる。**Dart 側の try/catch では絶対に防げない。**

WorkManager はこのアプリが使っているものではない。`google_mobile_ads` が
持ち込んでいる。

**デバッグビルドでは R8 が走らないので再現しない。** リリースビルドを
実機に入れるまで誰も気づけない種類の不具合なので、プラグインを増やした
ときや AGP を上げたときは、署名済みビルドで一度起動確認すること。

### 2. XML コメントにハイフンを2つ続けて書かない

`AndroidManifest.xml` と `Info.plist` の話。XML の仕様違反でパーサが弾き、
**Android/iOS のビルドだけ**が落ちる。`flutter test` も `flutter build web`
もすり抜ける。過去に一度踏んでいる。

`test/platform/manifest_xml_test.dart` が見張っているので、これらのファイルを
触ったら `flutter test` を通すこと。

## リポジトリの外にあるもの

### 署名鍵

`_keys_DO_NOT_COMMIT/`（git 管理外、フォルダごと .gitignore）

- `upload-keystore.jks` — alias `upload`、PKCS#12、有効期限 2054-03
- `keystore-credentials.txt` — パスワードと、GitHub Secrets 4件の対応表
- `android/key.properties` — 設定済み。これも git 管理外

**公開後にこの鍵を失うとアプリを更新できなくなる。** 2026-10-15 に一度
紛失して作り直している（未公開だったため無害だった）。

### AdMob

Android の本番 ID 設定済み。`lib/monetization/ads/ad_unit_ids.dart` が定義元で、
`AndroidManifest.xml` の `APPLICATION_ID` と手動同期する（マニフェストは
起動時に読まれる静的値なので Dart から差し替えられない）。片方だけ変えない。

iOS は本番 ID 未取得。`AdUnitIds` が `Platform.isAndroid` で分岐していて
iOS は常にテスト ID を返すので、Android 単独リリースの間は触らなくてよい。

**本番の広告は、ストア公開 → AdMob でリスティングにリンク → AdMob の審査
（2〜3日）が揃うまで配信されない。** 公開直後に広告が出ないのは正常。

### 課金商品

Play Console 側に作成済み・有効化済み。ID は
`lib/monetization/billing/product_ids.dart` が定義元で、**Play Console 側と
1文字でも違うと `queryProductDetails` が何も返さず購入ボタンが無反応になる。**

Play Console の1回限りのアイテムは「アイテム → 購入オプション → 特典」の
3階層。アプリが見るのはアイテム ID だけ。

## ビルドとリリース

- `flutter build appbundle --release --build-name X.Y.Z --build-number N`
- GitHub Actions の **Build the Android release bundle**（手動実行）でも同じ
  ものが出る。`version` に `1.0.0+2` のように入れると上書きできる
- Artifacts は **zip で落ちてくる**。展開して中の
  `app/outputs/bundle/release/app-release.aab` を Play に上げる
- 両ワークフローとも `runs-on` は `ubuntu-24.04` にピン留めしてある。
  `ubuntu-latest` に戻さないこと（勝手に OS が変わる）

**非 ASCII パスでは Android ビルドが通らない。** AGP がパスを拒否する。
`C:\Users\shima\claude\make10` は ASCII なので問題ない。

**NDK は手で入れる。** 初回ビルドで AGP が NDK を取りに行き、こう落ちる。

```
Package ndk not found.
Package 28.2.13676358 not found.
Android sdkmanager did not install NDK 28.2.13676358
```

Android SDK の cmdline-tools 23 で `sdkmanager` が廃止されて新しい `android`
CLI に置き換わり、パッケージ名も `ndk;28.2.13676358` から `ndk/28.2.13676358`
の書式に変わった。AGP が渡す古い書式の名前を受け付けない。build-tools は AGP が
自力で取れるので、引っかかるのは NDK だけ。要求される版は `flutter.ndkVersion`
で決まるので、エラーに出た版をそのまま入れる。

```
%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\bin\android.exe sdk install ndk/28.2.13676358
```

## ドキュメント

| 内容 | 場所 |
| --- | --- |
| 署名・ビルド・Play Console の全体手順 | `docs/release/android-release.md` |
| AdMob と課金の設定手順 | `docs/release/monetization-setup.md` |
| 掲載文・データセーフティ・レーティングの回答 | `store/play-listing.md` |
| スクリーンショットの撮り直し手順 | `store/android/README.md` |
| アイコンとストア画像の生成 | `tool/branding/generate_icons.py` |

プライバシーポリシーは `web/privacy.html`。GitHub Pages で
`https://shiaco22.github.io/make10/privacy.html` として公開される。

## 仕様書との不一致

`docs/superpowers/specs/2026-08-30-make10-app-design.md` の §1.1 は、いまだに
「広告・課金は v1 に含まない」と書いている。収益化を入れる前の記述で、実装と
矛盾している。仕様書を参照するときは注意すること。
