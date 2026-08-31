# Android リリース手順（Google Play）

MAKE10 を Google Play に出すまでの手順。**署名鍵まわりが唯一やり直しの効かない
部分**なので、そこだけ先に読んでほしい。

- パッケージ名: `com.nanaumi.make10`（公開後は**永久に変更不可**）
- 現在のバージョン: `pubspec.yaml` の `version: 1.0.0+1`
  （`1.0.0` = versionName、`1` = versionCode）

---

## 0. 前提：アップロード鍵の扱い

Play は「アップロード鍵で署名した .aab を受け取り、Google が保管する
アプリ署名鍵で署名し直して配信する」（Play App Signing）。開発者が管理するのは
**アップロード鍵**のほう。

- **この鍵を失うと、以後アプリを更新できなくなる。** Play サポートに
  アップロード鍵のリセットを申請すれば復旧はできるが、数日かかる。
- `upload-keystore.jks` とそのパスワードは、パスワードマネージャなど
  リポジトリの外に保管する。`.gitignore` で `*.jks` と
  `android/key.properties` はコミットされないようにしてある。

鍵の情報（別途受け取ったもの）:

| 項目 | 値 |
| --- | --- |
| ファイル | `upload-keystore.jks`（PKCS#12 形式） |
| エイリアス | `upload` |
| 鍵アルゴリズム | RSA 2048bit |
| 有効期限 | 2054年1月（Play の要件は 2033年10月以降、余裕あり） |

---

## 1. ローカルでビルドする場合

### 1-1. `android/key.properties` を置く

`android/key.properties.example` をコピーして、実際の値を入れる。

```
storePassword=<受け取ったパスワード>
keyPassword=<同じパスワード>
keyAlias=upload
storeFile=C:/keys/make10/upload-keystore.jks
```

`storeFile` は絶対パスにする。Windows でもスラッシュ区切りで書けば動く。
このファイルは git 管理外。

### 1-2. ASCII のみのパスにチェックアウトする

**これを忘れると必ず失敗する。** Android Gradle Plugin は非 ASCII を含む
パスを拒否するため、`...\ドキュメント\nanaumi\MAKE10` では Android ビルドが
通らない（README の該当節を参照）。

```
git archive HEAD | tar -x -C C:/dev/make10
cd C:/dev/make10
C:\flutter\bin\flutter.bat pub get
```

### 1-3. ビルド

```
C:\flutter\bin\flutter.bat build appbundle --release
```

出力: `build/app/outputs/bundle/release/app-release.aab`

### 1-4. デバッグ鍵で署名されていないか確認する

デバッグ鍵で署名された .aab も普通にビルドが通ってしまい、Play にアップロード
して初めて弾かれる。先に署名者を見ておく。

```
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

表示された SHA-256 が、アップロード鍵のもの（下記）と一致すること。

```
keytool -list -v -keystore C:/keys/make10/upload-keystore.jks -alias upload
```

一致しなければ `android/key.properties` が読まれていない。パスと綴りを確認する。

## 2. GitHub Actions でビルドする場合（推奨）

ローカルの作業パスが非 ASCII である問題を、CI 側で回避できる。

### 2-1. リポジトリに Secrets を登録する

GitHub → Settings → Secrets and variables → Actions → New repository secret

| 名前 | 中身 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `upload-keystore.jks` を base64 にした文字列（別途受け渡し） |
| `ANDROID_KEYSTORE_PASSWORD` | ストアパスワード |
| `ANDROID_KEY_PASSWORD` | 鍵パスワード（ストアと同じ） |
| `ANDROID_KEY_ALIAS` | `upload` |

base64 化を自分で行う場合:

```
# macOS / Linux
base64 -w0 upload-keystore.jks > keystore.b64
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) > keystore.b64
```

### 2-2. ワークフローを実行する

GitHub → Actions → **Build the Android release bundle** → Run workflow。
`version` を空にすると `pubspec.yaml` の値を使う。`1.0.1+2` のように
入れればその場で上書きできる。

完了後、実行ページの Artifacts から `app-release-aab` をダウンロードする。
`flutter analyze` と `flutter test` が通らなければビルドまで進まない。
署名者がアップロード鍵と一致するかも、ワークフロー内で検証している。

## 3. Play Console での作業

初回は「アプリを作成」から。以降の更新は 5 だけでよい。

1. **アプリを作成** — アプリ名 `MAKE10 - 10をつくる計算パズル`、既定の言語 日本語、
   アプリ / ゲーム = ゲーム、無料
2. **ストアの設定** — カテゴリ `パズル`、連絡先、
   プライバシーポリシー URL `https://shiaco22.github.io/make10/privacy.html`
3. **ストアの掲載情報** — `store/play-listing.md` の文面をそのまま貼る。
   アイコンは `store/icon-512.png`、
   フィーチャーグラフィックは `store/feature-graphic-1024x500.png`。
   **スクリーンショットは最低2枚必要**で、これだけは実機かエミュレータで撮る必要がある
   （`store/play-listing.md` 末尾に撮る画面の候補を書いてある）
4. **アプリのコンテンツ** — 以下をすべて申告する。回答案は `store/play-listing.md` にある
   - プライバシーポリシー
   - アプリのアクセス権 → 制限なし
   - 広告 → 広告なし
   - コンテンツのレーティング → アンケートに回答（全年齢になる想定）
   - 対象ユーザー
   - データセーフティ → すべて「収集しない」
   - 政府アプリ / 金融商品 / 健康 → いずれも該当なし
5. **リリースを作成** — 製品版（または内部テスト）に `.aab` をアップロードし、
   リリースノートを書いて「審査に送信」

## 4. リリースの前に確認すること

- [ ] `flutter test` と `flutter analyze` が通る
- [ ] `pubspec.yaml` の `version` を上げた（**versionCode は前回より必ず大きく**）
- [ ] `.aab` の署名者がアップロード鍵と一致する
- [ ] `targetSdk = 36`（2026-08-31 以降、Play の新規アプリ・更新の必須要件）
- [ ] 実機で一度インストールして起動する（内部テストトラックが手軽）
- [ ] プライバシーポリシーの URL が実際に開ける

## 5. 更新をリリースするとき

1. `pubspec.yaml` の `version` を上げる（例: `1.0.1+2`）
2. 変更をコミットして `main` に入れる
3. Actions からワークフローを実行し、`.aab` を取得
4. Play Console で新しいリリースを作成してアップロード

---

## 補足：まだ入れていないもの

- **難読化 (`--obfuscate --split-debug-info`)** — 本体は Dart の AOT コードなので
  Java 側の R8 で得られるものは少なく、初回リリースでは有効にしていない。
  入れる場合はシンボルファイルの保管とクラッシュ解析の手順もセットで用意すること。
- **iOS 版** — `ios/` は Flutter のテンプレートのまま。App Store 提出には
  Bundle ID の設定、証明書とプロビジョニングプロファイル、
  App Store Connect でのアプリ作成が別途必要。
