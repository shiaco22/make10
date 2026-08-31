import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'widgets/responsive.dart';

class Make10App extends StatelessWidget {
  const Make10App({super.key});

  static const Color _seedColor = Colors.indigo;

  /// アプリの実際のライトテーマ。build() と、テスト側が「実物のテーマ」を
  /// 手で組み直さずに参照できるよう、トップレベルの定数として公開する。
  static final ThemeData lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    useMaterial3: true,
  );

  /// 同じシード色から作るダークテーマ。
  static final ThemeData darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  /// 画面の向きを端末種別に応じて固定/解放する（仕様 §9.2）。
  ///
  /// 判定基準は [uiScale] と揃え、ビューポートの短辺
  /// (`MediaQuery.sizeOf(context).shortestSide`) を [kTabletBreakpoint] と
  /// 比較する。電話サイズなら縦向きに固定し、タブレットサイズなら空リスト
  /// を渡して制約を解除する（`SystemChrome.setPreferredOrientations` は
  /// 空リストで「どの向きでも良い」を表す）。
  ///
  /// [main] はまだ `MediaQuery` が存在しない時点で走るため、電話かタブレット
  /// かをそこでは判定できない。`MediaQuery` を参照できるこの build() が、
  /// その判定ができる最初の場所になる。
  ///
  /// 呼び出しは毎ビルド行うが、これは無害かつ自己修復的である: 電話は
  /// 縦向きに固定されている以上ビューポートは変化せず、タブレットは回転
  /// しても短辺が不変なので、再評価しても結果は変わらない。逆に、この
  /// 依存 (`MediaQuery.sizeOf`) があることで回転やウィンドウのリサイズが
  /// 起きるたびに自動で再評価される。
  void _updateOrientationLock(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    SystemChrome.setPreferredOrientations(
      shortestSide < kTabletBreakpoint
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ]
          : const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    _updateOrientationLock(context);
    return MaterialApp(
      title: 'MAKE 10',
      theme: lightTheme,
      // themeMode は既定 (ThemeMode.system) のままにして、明暗はシステム
      // 設定に委ねる。
      darkTheme: darkTheme,
      home: const HomeScreen(),
    );
  }
}
