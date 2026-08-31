# Google Play ストア掲載用素材

`https://play.google.com/console` のストア掲載情報にそのままアップロードできる
スクリーンショットです。

## 収録内容

| ディレクトリ | 解像度 | 比率 | 枚数 | Play Console の項目 |
|---|---|---|---|---|
| `phone/` | 1080×1920 | 1.78 | 8 | スマートフォンのスクリーンショット |
| `tablet-7/` | 1200×1920 | 1.60 | 5 | 7 インチタブレットのスクリーンショット |
| `tablet-10/` | 1600×2560 | 1.60 | 5 | 10 インチタブレットのスクリーンショット |

タブレット 2 種は論理サイズがそれぞれ 800×1280 / 1067×1707 で、いずれも
タブレット向けレイアウト（拡大とグループ化、`lib/ui/widgets/responsive.dart`）
が適用された状態を撮影しています。スマートフォンは 411×731 で、拡大なしの
レイアウトです。

## Play の要件との対応

| 要件 | 状態 |
|---|---|
| PNG または JPEG | PNG |
| 各辺 320〜3840 px | 最小 1080、最大 2560 |
| 長辺が短辺の 2 倍以内 | 最大 1.78 |
| スマートフォンは 2〜8 枚 | 8 枚 |

`flutter build apk --release` で作成したビルドを撮影しているため、
デバッグバナーは写っていません。ステータスバーは Android のデモモードで
時刻 9:00・電池満充電・通知なしに固定しています。

## 撮り直す手順

エミュレータで実行します。デバッグビルドで撮るとデバッグバナーが写り込み、
そのままでは審査に出せません。

```
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0900
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false

adb shell wm size 1080x1920 && adb shell wm density 420   # スマートフォン
adb shell wm size 1200x1920 && adb shell wm density 240   # 7 インチ
adb shell wm size 1600x2560 && adb shell wm density 240   # 10 インチ

adb exec-out screencap -p > 撮影先.png

adb shell wm size reset && adb shell wm density reset
adb shell am broadcast -a com.android.systemui.demo -e command exit
```

**このリポジトリの現在の場所からは Android ビルドができません。** Android
Gradle Plugin がパスに含まれる非 ASCII 文字（`ドキュメント`）を拒否するため、
ASCII のみのパスにコピーしてからビルドしてください。詳細はリポジトリ直下の
README を参照。

## まだ足りない素材

ストア掲載にはスクリーンショットのほかに次が必要です。いずれも未作成です。

- **アプリアイコン** 512×512 の 32bit PNG。`android/app/src/main/res/mipmap-*/ic_launcher.png`
  は現在 `flutter create` が生成した既定の Flutter アイコンのままで、
  独自のアイコンに差し替える必要があります。
- **フィーチャーグラフィック** 1024×500 の PNG または JPEG（アルファなし）。
- ストアの説明文、プライバシーポリシーの URL、コンテンツレーティングの申告。
